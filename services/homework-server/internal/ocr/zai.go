package ocr

// NewZAI uses the public Chat Completions schema documented for GLM-5.3-Flash.
// No fallback endpoint, client impersonation or additional runtime is involved.
// The caller explicitly supplies its account's endpoint, key and allowed model.
func NewZAI(baseURL, apiKey, model string) *OpenAICompatEngine {
	e := NewOpenAICompat(baseURL, apiKey, model)
	e.name = "zai"
	e.options = map[string]any{
		"temperature": 1,
		"max_tokens":  16384,
		"thinking":    map[string]string{"type": "enabled"},
	}
	return e
}
