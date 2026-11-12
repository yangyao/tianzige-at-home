# upload-ios · 手机上传

SwiftUI 原生 App。

## 状态

**未开始。** 当前用 `apps/upload-web/upload.html` 在 Safari 里替代。

## 核心场景

家长在微信/QQ 里截了图 → 切到本 App → 直接粘贴 → 上传 → 走人。

## 计划

- 主界面只有三块：图片区、备注框、上传按钮
- 支持从剪贴板读图（`UIPasteboard.general.image`）
- 支持相册多选、拍照
- 上传即 POST，不做进度等待，成功只弹一条 toast
- 底部保留「最近上传」列表（读 `GET /batches`）
- 失败的批次可点「重新识别」（`POST /batch/{id}/rerun`）

## 与网页版的差别

网页版已经够用的话，这个 App 的唯一价值是：**贴图少两步**（不用开浏览器、不用找网址）。所以只做这一件事，不要加功能。
