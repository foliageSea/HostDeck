# WebOS 独立桌面示例

这是占满浏览器视口的独立桌面应用，不是嵌入普通页面的示例。顶栏、桌面快捷方式、小组件、窗口和 Dock 构成整个应用界面；介绍内容放在欢迎应用窗口内。

示例仅消费 `@host-deck/webos` 的编译产物，不需要 HostDeck 后端、SSH、Pinia、UnoCSS 或组件自动导入。

在仓库根目录运行：

```sh
pnpm --dir host-deck-ui dev:webos-demo
```

访问 `http://localhost:5180`。通过 Dock 或启动台打开欢迎、计数器和编辑器；编辑器支持未保存内容的关闭确认。

验证：

```sh
pnpm --dir host-deck-ui build:webos-demo
pnpm --dir host-deck-ui test:webos-demo
pnpm --dir host-deck-ui verify:webos-package
```
