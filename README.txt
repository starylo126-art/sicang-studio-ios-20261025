私藏动捕室 · iOS 工程（iOS 17 及以上）

当前交付状态
已有原生 Swift 工程、离线资源导入器、手机本地 HTTP 服务、相机权限处理、系统分享导出、免费云编译工作流。
已在 GitHub 标准 macos-15 runner 上通过 Xcode Release 编译，生成 arm64 未签名 IPA。尚未签名安装或进行 iPhone 真机验收。
已下载的成品：私藏动捕室_iOS_未签名.ipa。首次使用直接从下方第 4 步开始，无需再次编译。
网页、本地资源及云编译检查结果见旁边的《界面与iOS验证报告.json》。
构建记录：https://github.com/starylo126-art/sicang-studio-ios-20261025/actions/runs/40169082049
公开仓库：https://github.com/starylo126-art/sicang-studio-ios-20261025

不买 Mac、不买开发者会员的安装路线
1. 在自己的 GitHub 账户新建仓库。只上传本目录的内容（包含隐藏的 .github 目录），不要上传旁边的 .scstudio 素材包。
   公开仓库的标准 GitHub 托管 runner 免费。本工程仅包含通用 App 外壳和资源打包器，不含用户的角色图、配色或动捕模型。
   若不希望公开代码，可以使用私有仓库的剩余免费额度；有付款方式的账户须先确认阻止超额计费。用户要求零支出，不使用付费 larger runner。
2. 仓库 Actions → Build free unsigned iOS app → Run workflow。
   工作流使用标准 macos-15，只手动触发，超时 15 分钟，产物只保留 1 天，不需要 Apple 密码或证书。
3. 编译成功后下载 PrivateWardrobe-unsigned-IPA，解压得到 PrivateWardrobe-unsigned.ipa。
   未签名 IPA 不能直接在手机上点开安装，必须执行下一步。
4. Windows 下载官网 Sideloadly（免费），按其官方 Windows 安装说明准备 iTunes/iCloud 组件。
   用 USB 连接并信任 iPhone，将 IPA 拖进 Sideloadly，使用自己的免费 Apple 账户签名安装。
   密码和双重验证只在你选择的签名工具/Apple 验证界面中输入，不写入源码、GitHub 或聊天。
5. 按 iPhone 系统提示信任开发者，必要时在「设置 → 隐私与安全性 → 开发者模式」开启开发者模式并重启。
6. 将“私藏衣橱.scstudio”拷到 iPhone 的「文件」。可用已有的文件传输方式，也可用 USB 文件共享。
   App 首次打开点「导入离线衣橱」，选择资源包。以后打开无需电脑或网络；更换素材包在「工具 → ? → 更换离线衣橱资源包」。
7. 点「工具 → 开启摄像头」，允许相机权限；面向镜头正常睁眼，再点「正脸校准」。

免费签名与续签
Apple 免费 Personal Team 的描述文件有效期为 7 天，每台设备最多同时 3 个免费开发 App。
每 7 天到期前，用同一个 Apple 账户、同一个 Bundle ID 覆盖续签同一个 App；不需要每周重新编译。
Sideloadly 支持 USB / 同一 Wi-Fi 下后台续签，电脑须运行其续签服务，具体开关按官网说明。
不要先删除 App；卸载会删除手机中的收藏、绑定与导入素材。建议导出绑定并保留原资源包。

界面和功能
- 顶部品牌栏已移除，取景工具默认收起；底部“工具 / 衣橱 / 动捕 / 绑定”按需展开，再点一次收起。
- 手机窄屏同时保留一个操作面板，角色预览仍在上方；纯净画面有触屏退出按钮。
- 衣橱沿用原有角色、换装、配色、收藏。手机与电脑各自保存，暂不云同步。
- 头部转动与肩膀、衣服分离；沿用已有闭眼、嘴型、转脸透视、前后发层物理。
- iOS 优先录制 MP4；编码按系统实际支持选择，文件扩展名与实际 MIME 一致。
- 录制无声，点击结束后再点击“保存 / 分享”；可存到文件或使用系统支持的相册操作。
- App 切到后台时停止相机、结束当前录制；回到前台后需要主动重新开启相机。
- 固定手机内地址 127.0.0.1:18765，只监听本机；模型和计算都在设备本地，没有社区、登录、上传接口。
- 资源逐文件 SHA-256 校验，失败保留旧包；最大资源包 250 MB，单次导出 150 MB。
- 本实现复用二维图层的自定义 2.5D 绑定，不是 Spine Editor 工程，不宣称与 Avvy 实机效果完全一致。

更新资源
修改桌面版后，可在已安装 Node.js 的电脑运行：
node tools/make-resource-pack.mjs ../avatar-studio ../私藏衣橱.scstudio
重新导入新的资源包即可；若仅修改网页功能，无需重新编译 iOS App。收藏与绑定保存在固定的本地来源内。

真机验收尚待完成
Xcode 编译 → 免费签名安装 → 开飞行模式导入并换装 → 前摄权限与实际追踪 → 闭眼/左右转脸/肩膀稳定 → MP4 录制保存 → PNG 透明导出 → 切后台再恢复 → 覆盖续签后数据保留。
若 iPhone 低于 iOS 17，此工程不支持；不要仅在签名工具中伪改最低版本。

官方依据（核查日期 2026-10-25）
Apple 免费账户和 7 天限制：https://developer.apple.com/help/account/basics/about-your-developer-account/
Apple 开发者模式：https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device
GitHub Actions 免费范围：https://docs.github.com/en/billing/concepts/product-billing/github-actions
Sideloadly 免费 Windows 工具：https://sideloadly.io/index.html
Safari 17 的 OffscreenCanvas WebGL：https://developer.apple.com/documentation/safari-release-notes/safari-17-release-notes
Safari MP4 录制：https://webkit.org/blog/11353/mediarecorder-api/
