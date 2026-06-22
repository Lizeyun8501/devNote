# DevNote Web Clipper 图标

`manifest.json` 引用了以下 PNG 图标文件：

- `icon16.png`  (16×16)
- `icon48.png`  (48×48)
- `icon128.png` (128×128)

由于本仓库无法直接提交二进制 PNG 资源，这里提供了矢量源文件 `../icon.svg`，需要将其转换为上述三种尺寸的 PNG 后放入本目录。

## 转换方法

使用 ImageMagick：

```bash
cd extensions/web-clipper
convert -background none -resize 16x16  icon.svg icons/icon16.png
convert -background none -resize 48x48  icon.svg icons/icon48.png
convert -background none -resize 128x128 icon.svg icons/icon128.png
```

或使用 `rsvg-convert`：

```bash
rsvg-convert -w 16  -h 16  icon.svg -o icons/icon16.png
rsvg-convert -w 48  -h 48  icon.svg -o icons/icon48.png
rsvg-convert -w 128 -h 128 icon.svg -o icons/icon128.png
```

或使用 Inkscape：

```bash
inkscape -w 16  -h 16  icon.svg -o icons/icon16.png
inkscape -w 48  -h 48  icon.svg -o icons/icon48.png
inkscape -w 128 -h 128 icon.svg -o icons/icon128.png
```

转换完成前，扩展加载时图标会显示为默认占位图，但功能不受影响。
