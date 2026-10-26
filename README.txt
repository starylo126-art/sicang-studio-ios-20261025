私藏动捕室 · iOS 1.2.6 / build 9（iOS 17及以上）

此目录是通用Swift外壳，不含个人角色图片、配色或动捕模型。个人资源只在Windows本地合入IPA。
仓库：https://github.com/starylo126-art/sicang-studio-ios-20261025
构建：GitHub Actions手动触发build-ios.yml，使用标准macos-15 runner，不使用付费大型runner。

本地资源与打包
node tools/make-resource-pack.mjs ../avatar-studio ../私藏衣橱.scstudio
资源包逐文件记录路径、字节数和SHA-256，App导入时验证。将资源包作为StarterResources.scstudio合入编译出的通用IPA，保持可执行文件不变。
最终文件为“私藏动捕室_v13_iOS_含衣橱待签名.ipa”。构建、签名、安装及真机体验是不同的验证阶段，实际状态见本地主项目的“iOS_v13安装包验证.json”。

Windows签名
使用已配置的iLoader和自己的Apple账户。USB连接并解锁iPhone，选择设备后导入最终IPA；等待“操作完成”。
密码和验证码只由本人在工具窗口输入，不写入源码、公开仓库或聊天。
使用相同账户及Bundle ID覆盖更新或续签，不先卸载App。首次打开build 9会导入随包资源，工具 → ? 应显示“资源 v13 · iOS 1.2.6”。

实现与检查范围
ARKit在本机追踪，仅向WebView传送姿态参数。忙碌时只保留最新参数；相机退出或切后台会释放。
v13根据投影的屏幕轴和解剖左右眼确定输入方向，再应用用户选择的镜像模式；相关回归结果见主项目检查记录。
图层绑定为自定义2.5D实现，不是完整Spine或Cubism工程，不宣称与Avvy效果等价。
网页、模拟与GPU检查不能代替真人iPhone摄像头验收。上一版用户反馈方向仍反、抬头轮廓不自然，v13针对这两项重新处理。
