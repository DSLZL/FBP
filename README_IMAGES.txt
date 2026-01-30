# 自定义图标与缩略图设置指南

为了让您的 Mod 看起来更专业，您可以添加自定义图标和缩略图。

## 1. 缩略图 (Thumbnail)
- **文件名**: `thumbnail.png`
- **存放位置**: `Factorio_Blueprint_Printer/` (Mod 根目录)
- **推荐尺寸**: 144x144 像素。
- **配置**: 完成后，在 `info.json` 中添加 `"thumbnail": "thumbnail.png"`。

## 2. 快捷键图标 (Icons)
- **存放位置**: `Factorio_Blueprint_Printer/graphics/icons/`
- **文件名**:
  - 放置图标: `icon_placement.png`
  - 拆除图标: `icon_deconstruction.png`
- **推荐尺寸**: 64x64 像素。
- **配置**: 完成后，修改 `data.lua`。我已经在代码中为您准备好了注释掉的配置，您只需取消注释并删除原有的基础游戏引用即可。

## 注意事项
- 必须是 PNG 格式。
- 请确保文件名与上述一致，否则 Mod 会因为找不到文件而崩溃。
