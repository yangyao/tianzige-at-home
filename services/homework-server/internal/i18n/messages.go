package i18n

// entry 一个 key 的中英文案。
type entry struct {
	zh string
	en string
}

// messages 是全部面向用户的错误/提示文案。
// key 用语义名，不要拿中文当 key。中文保持服务端原有措辞。
var messages = map[string]entry{
	// 通用 / 路由
	"err.method_not_allowed": {"请求方法不支持", "That method isn't supported"},
	"err.api_not_found":      {"接口不存在", "No such endpoint"},
	"err.batch_not_found":    {"批次不存在", "Batch not found"},
	"err.image_not_found":    {"图片不存在", "Photo not found"},
	"err.internal":           {"服务内部错误，请查看服务端日志", "Something went wrong on the server — check the server logs"},

	// 查询参数
	"err.invalid_date_format": {"日期格式应为 YYYY-MM-DD", "The date should be YYYY-MM-DD"},
	"err.from_to_required":    {"from 与 to 都是必填参数", "Both from and to are required"},
	"err.date_order":          {"结束日期不能早于开始日期", "The end date can't be before the start date"},
	"err.max_days":            {"一次最多查询 62 天", "Up to 62 days at a time"},
	"err.limit_range":         {"limit 应为 1–50 的整数", "limit should be a whole number from 1 to 50"},

	// 上传
	"err.file_too_large":   {"单张图片不能超过 20MB", "Each photo must be under 20 MB"},
	"err.upload_parse":     {"上传表单解析失败：%s", "Couldn't read the upload: %s"},
	"err.no_files":         {"请至少上传一张图片", "Pick at least one photo"},
	"err.too_many_files":   {"一次最多 %d 张图片", "Up to %d photos at a time"},
	"err.note_too_long":    {"备注不能超过 %d 字", "The note can be at most %d characters"},
	"err.read_upload":      {"读取上传文件失败", "Couldn't read the uploaded file"},
	"err.unsupported_type": {"只接受 jpg/png/heic/webp 图片", "Only jpg, png, heic or webp photos"},
	"err.temp_file":        {"写入临时文件失败", "Couldn't write a temporary file"},
	"err.save_upload":      {"保存上传文件失败", "Couldn't save the uploaded file"},

	// AI 设置
	"ai.same_origin_required": {"请从 NAS 上传页打开 AI 设置", "Open AI settings from the NAS upload page"},
	"ai.unavailable":          {"AI 设置暂不可用", "AI settings aren't available right now"},
	"ai.json_required":        {"请使用 JSON 提交设置", "Send the settings as JSON"},
	"ai.invalid_body":         {"AI 设置格式不正确或内容过长", "The AI settings are malformed or too long"},
	"ai.single_body":          {"只能提交一组 AI 设置", "Send just one set of AI settings"},
	"ai.test_ok":              {"连接成功，模型接受了图片请求。测试没有修改已保存的配置。", "Connected — the model accepted the image request. The test didn't change your saved settings."},
	"ai.test_failed":          {"模型测试没通过：%s", "The model didn't respond: %s"},

	// aiconfig 返回的校验/持久化错误
	"ai.err.read_config":          {"无法读取 AI 配置", "Couldn't read the AI settings"},
	"ai.err.config_format":        {"AI 配置文件格式不正确", "The AI settings file is malformed"},
	"ai.err.missing_key":          {"AI 配置缺少密钥", "The AI settings have no API key"},
	"ai.err.protect_config":       {"无法保护 AI 配置文件", "Couldn't secure the AI settings file"},
	"ai.err.key_required_new_url": {"更换 API 地址后，请填写新密钥；本地服务可选择无需密钥", "After changing the API address, enter a new key — local services can choose no key"},
	"ai.err.key_required":         {"请填写 API 密钥，或选择此服务无需密钥", "Enter an API key, or choose that this service needs none"},
	"ai.err.profile":              {"请选择 OpenAI 兼容或 Z.AI 服务类型", "Choose OpenAI-compatible or Z.AI"},
	"ai.err.base_url":             {"API 地址应为完整的 http:// 或 https:// 地址，不包含密钥或查询参数", "The API address should be a full http:// or https:// address with no key or query string"},
	"ai.err.model":                {"请填写模型名称（最多 200 字节）", "Enter a model name (up to 200 bytes)"},
	"ai.err.key_format":           {"密钥格式不正确", "That API key doesn't look right"},
	"ai.err.base_url_long":        {"API 地址过长", "The API address is too long"},
	"ai.err.mkdir":                {"无法创建 AI 配置目录", "Couldn't create the AI settings folder"},
	"ai.err.protect_dir":          {"无法保护 AI 配置目录", "Couldn't secure the AI settings folder"},
	"ai.err.encode":               {"无法编码 AI 配置", "Couldn't encode the AI settings"},
	"ai.err.write":                {"无法写入 AI 配置", "Couldn't write the AI settings"},
	"ai.err.save":                 {"无法保存 AI 配置", "Couldn't save the AI settings"},
	"ai.err.replace":              {"无法替换 AI 配置", "Couldn't replace the AI settings"},
}

// sources 把 aiconfig 的中文错误原文映射到 key，供 FromSource 使用。
// 原文改动时这里会失配并回退原文，不会让接口报错。
var sources = map[string]string{
	"无法读取 AI 配置":   "ai.err.read_config",
	"AI 配置文件格式不正确": "ai.err.config_format",
	"AI 配置缺少密钥":    "ai.err.missing_key",
	"无法保护 AI 配置文件": "ai.err.protect_config",
	"更换 API 地址后，请填写新密钥；本地服务可选择无需密钥":                "ai.err.key_required_new_url",
	"请填写 API 密钥，或选择此服务无需密钥":                        "ai.err.key_required",
	"请选择 OpenAI 兼容或 Z.AI 服务类型":                     "ai.err.profile",
	"API 地址应为完整的 http:// 或 https:// 地址，不包含密钥或查询参数": "ai.err.base_url",
	"请填写模型名称（最多 200 字节）":                           "ai.err.model",
	"密钥格式不正确":      "ai.err.key_format",
	"API 地址过长":     "ai.err.base_url_long",
	"无法创建 AI 配置目录": "ai.err.mkdir",
	"无法保护 AI 配置目录": "ai.err.protect_dir",
	"无法编码 AI 配置":   "ai.err.encode",
	"无法写入 AI 配置":   "ai.err.write",
	"无法保存 AI 配置":   "ai.err.save",
	"无法替换 AI 配置":   "ai.err.replace",
}
