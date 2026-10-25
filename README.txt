私藏动捕室 · iOS 1.2.4 / build 7（iOS 17及以上）

此目录是通用Swift外壳，不含个人角色图片、配色或动捕模型。个人资源只在Windows本地合入IPA。
本轮标准macos-15 runner已完成Release编译：
https://github.com/starylo126-art/sicang-studio-ios-20261025/actions/runs/40208641119
提交：45749d427fab8ee992c016966c53e59506af4475
仓库：https://github.com/starylo126-art/sicang-studio-ios-20261025

本地资源与打包
在已安装Node.js的电脑运行：
node tools/make-resource-pack.mjs ../avatar-studio ../私藏衣橱.scstudio
资源包按文件记录路径、字节数和SHA-256；App导入时逐文件验证。打包前须确认资源包与当前源目录完全一致。
将资源包作为StarterResources.scstudio合入已编译的通用IPA，保持编译出的可执行文件不变。
本版最终名称为“私藏动捕室_v11_iOS_含衣橱待签名.ipa”。编译成功和生成IPA不等于已经签名或安装，实际状态见“iOS_v11安装包验证.json”。

Windows免费签名
使用已配置的iLoader和自己的Apple账户。USB连接并解锁iPhone，选择设备后导入最终IPA；等待“操作完成”。
密码和验证码只由本人在工具窗口输入，不写入源码、公开仓库或聊天。
使用相同账户及Bundle ID覆盖更新或续签，不要先卸载App。免费签名仍需定期续签，不必每次重新编译外壳。
首次启动build 7会导入随包资源，工具 → ? 应显示“资源 v11 · iOS 1.2.4”。

本版功能
v11资源加强横向头发惯性，按发长软限幅；80款有效头饰共189个语义区域独立控制外缘、垂带和根部，身体混合部件保留身体归属。
两处作者说明文字在运行时隐藏，源PNG不删改；长按切换角色为0.8秒。
本机ARKit人脸追踪仅向WebView传姿态参数，网页不运行WASM人脸推理。相机切后台自动释放；返回后重新开启。
离线衣橱、独立物件调色、收藏、绑定及系统分享仍在本机运行，没有社区或上传功能。
本实现是自定义2.5D图层绑定，不是完整Spine或Cubism工程，不宣称与Avvy完全一致。

验证
头饰对照页面、GPU与单元测试最终结果由主项目检查记录提供。本轮摄像头实际手感和性能需在更新后的iPhone上确认，浏览器测试不能代替真机验收。
