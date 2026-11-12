// Package aiconfig stores one active OpenAI-compatible provider and publishes immutable model pairs.
package aiconfig

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/yangyao/tianzige-at-home/homework-server/internal/ocr"
	"github.com/yangyao/tianzige-at-home/homework-server/internal/parse"
)

type Config struct {
	Profile string `json:"profile"`
	BaseURL string `json:"base_url"`
	Model   string `json:"model"`
	APIKey  string `json:"api_key"`
	NoAuth  bool   `json:"no_auth"`
}

// View intentionally has no field capable of returning a secret.
type View struct {
	Profile   string `json:"profile"`
	BaseURL   string `json:"base_url"`
	Model     string `json:"model"`
	HasAPIKey bool   `json:"has_api_key"`
	NoAuth    bool   `json:"no_auth"`
}

type Manager struct {
	mu      sync.RWMutex
	writeMu sync.Mutex
	path    string
	config  Config
	engine  ocr.Engine
	parser  parse.Parser
}

// New preserves the existing environment-defined engines until a Web configuration is saved.
func New(path string, seed Config, engine ocr.Engine, parser parse.Parser) (*Manager, error) {
	m := &Manager{path: path, config: seed, engine: engine, parser: parser}
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return m, nil
	}
	if err != nil {
		return nil, fmt.Errorf("无法读取 AI 配置")
	}
	var c Config
	if json.Unmarshal(data, &c) != nil {
		return nil, fmt.Errorf("AI 配置文件格式不正确")
	}
	c, err = normalize(c)
	if err != nil {
		return nil, err
	}
	if !c.NoAuth && c.APIKey == "" {
		return nil, fmt.Errorf("AI 配置缺少密钥")
	}
	if err := os.Chmod(path, 0600); err != nil {
		return nil, fmt.Errorf("无法保护 AI 配置文件")
	}
	m.config = c
	m.engine, m.parser = build(c)
	return m, nil
}

func (m *Manager) View() View {
	m.mu.RLock()
	defer m.mu.RUnlock()
	c := m.config
	return View{Profile: c.Profile, BaseURL: c.BaseURL, Model: c.Model, HasAPIKey: c.APIKey != "", NoAuth: c.NoAuth}
}

func (m *Manager) Models() (ocr.Engine, parse.Parser) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.engine, m.parser
}

// resolve never carries a saved credential to a different endpoint implicitly.
func (m *Manager) resolve(input Config) (Config, error) {
	c, err := normalize(input)
	if err != nil {
		return c, err
	}
	m.mu.RLock()
	current := m.config
	m.mu.RUnlock()
	if c.NoAuth {
		c.APIKey = ""
	} else if c.APIKey == "" {
		if c.BaseURL != strings.TrimRight(current.BaseURL, "/") {
			return c, fmt.Errorf("更换 API 地址后，请填写新密钥；本地服务可选择无需密钥")
		}
		c.APIKey = current.APIKey
	}
	if !c.NoAuth && c.APIKey == "" {
		return c, fmt.Errorf("请填写 API 密钥，或选择此服务无需密钥")
	}
	return c, nil
}

func (m *Manager) Save(input Config) (View, error) {
	m.writeMu.Lock()
	defer m.writeMu.Unlock()
	c, err := m.resolve(input)
	if err != nil {
		return View{}, err
	}
	if err := persist(m.path, c); err != nil {
		return View{}, err
	}
	e, p := build(c)
	m.mu.Lock()
	m.config = c
	m.engine = e
	m.parser = p
	m.mu.Unlock()
	return m.View(), nil
}

func (m *Manager) Test(ctx context.Context, input Config) error {
	c, err := m.resolve(input)
	if err != nil {
		return err
	}
	e, _ := build(c)
	if err := e.(*ocr.OpenAICompatEngine).Probe(ctx); err != nil {
		message := err.Error()
		if c.APIKey != "" {
			message = strings.ReplaceAll(message, c.APIKey, "[已隐藏]")
		}
		return errors.New(message)
	}
	return nil
}

func normalize(c Config) (Config, error) {
	c.Profile = strings.TrimSpace(c.Profile)
	c.BaseURL = strings.TrimRight(strings.TrimSpace(c.BaseURL), "/")
	c.BaseURL = strings.TrimSuffix(c.BaseURL, "/chat/completions")
	c.Model = strings.TrimSpace(c.Model)
	c.APIKey = strings.TrimSpace(c.APIKey)
	if c.Profile != "openai" && c.Profile != "zai" {
		return c, fmt.Errorf("请选择 OpenAI 兼容或 Z.AI 服务类型")
	}
	u, err := url.Parse(c.BaseURL)
	if err != nil || u.Hostname() == "" || (u.Scheme != "http" && u.Scheme != "https") || u.User != nil || u.RawQuery != "" || u.Fragment != "" {
		return c, fmt.Errorf("API 地址应为完整的 http:// 或 https:// 地址，不包含密钥或查询参数")
	}
	if c.Model == "" || len(c.Model) > 200 {
		return c, fmt.Errorf("请填写模型名称（最多 200 字节）")
	}
	if len(c.APIKey) > 4096 || strings.ContainsAny(c.APIKey, "\r\n") {
		return c, fmt.Errorf("密钥格式不正确")
	}
	if len(c.BaseURL) > 2048 {
		return c, fmt.Errorf("API 地址过长")
	}
	return c, nil
}

func build(c Config) (ocr.Engine, parse.Parser) {
	var e *ocr.OpenAICompatEngine
	var p *parse.LLMParser
	if c.Profile == "zai" {
		e = ocr.NewZAI(c.BaseURL, c.APIKey, c.Model)
		p = parse.NewZAIParser(c.BaseURL, c.APIKey, c.Model)
	} else {
		e = ocr.NewOpenAICompat(c.BaseURL, c.APIKey, c.Model)
		p = parse.NewLLMParser(c.BaseURL, c.APIKey, c.Model)
	}
	e.AllowNoKey(c.NoAuth)
	p.AllowNoKey(c.NoAuth)
	return e, p
}

func persist(path string, c Config) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return fmt.Errorf("无法创建 AI 配置目录")
	}
	if err := os.Chmod(dir, 0700); err != nil {
		return fmt.Errorf("无法保护 AI 配置目录")
	}
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return fmt.Errorf("无法编码 AI 配置")
	}
	f, err := os.CreateTemp(dir, ".ai-provider-*")
	if err != nil {
		return fmt.Errorf("无法写入 AI 配置")
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if _, err = f.Write(data); err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err != nil || closeErr != nil {
		return fmt.Errorf("无法保存 AI 配置")
	}
	if err := os.Rename(tmp, path); err != nil {
		return fmt.Errorf("无法替换 AI 配置")
	}
	return nil
}
