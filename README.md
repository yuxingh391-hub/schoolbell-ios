# 今日课表

适用于 iOS 18 及以上的个人离线课表。任务开始时响上课铃，也可以设下课铃。铃声是随 App 打包的仿老式校园电铃。添加眼保健操后，到点响短铃，点通知就播放你导入的完整版录音。

## 在 Windows 上打包

1. 解压源码 ZIP，在 GitHub 新建一个 **公共**仓库。公共仓库的标准 macOS 构建环境免费。源码会公开，个人课表和眼保健操录音都在安装后直接存进手机。
2. 把项目根目录里的 `App`、`.github`、`project.yml` 和本说明推送到仓库的 `main` 分支。务必保留 `.github/workflows/ios.yml` 的完整路径。用 Git 时可以在解压后的目录中运行以下命令，换成你自己的 GitHub 仓库地址。

   ```powershell
   git init -b main
   git add App .github project.yml README.md
   git commit -m "Add offline school bell app"
   git remote add origin https://github.com/你的用户名/你的仓库名.git
   git push -u origin main
   ```

3. 在仓库的 **Actions** 中打开 **Build iPhone IPA**，等构建完成。在运行详情底部的 **Artifacts** 下载 **SchoolBell-iPhone**，解压得到 `SchoolBell.ipa`。也可在 Actions 页面手动运行构建。

## 在 iPhone 上安装

1. 按 [AltStore 官方 Windows 安装说明](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)，在 Windows 安装 AltServer，再连接 iPhone 安装 AltStore Classic。签名用免费 Apple 账号即可。按手机提示启用开发者模式并信任自己的开发者证书。
2. 将 `SchoolBell.ipa` 传到 iPhone 的「文件」，在 AltStore 的 **My Apps** 点 **＋**，选中它。AltStore 会使用你的账号签名。Windows 上的 AltServer 此时需要运行，手机可以通过 USB 或同一 Wi-Fi 连接。
3. 用免费签名安装的 App 在 7 天后到期。在到期前，运行 Windows 上的 AltServer，连接 iPhone，在 AltStore 中点 **Refresh All**。续签和安装需要网络，日常使用在手机端完成。[续签说明](https://faq.altstore.io/altstore-classic/your-altstore)

## 第一次试用

1. 打开「今日课表」，点「开启定时铃声」，允许通知。先在「声音」里试听上课铃和下课铃。
2. 关掉静音和专注模式。添加一个两分钟后开始的任务，锁屏并打开飞行模式，验证开始时间到时能否听到上课铃。需要下课铃的话，开启对应开关并设置结束时间。
3. 从「声音」导入手机里已有的眼保健操录音，例如 MP3、M4A 或 WAV。试听后添加一项「眼保健操」，验证点开到时通知会播放原录音。安装包内置两段电铃，眼保健操完整版由你导入。

重复安排支持每天、工作日或自选星期。重复安排的开始和结束须在同一天。App 最多登记 60 条待响铃通知，每个自选星期的开始或结束各占一条。静音模式和专注模式会影响铃声，锁屏时自动响的是短铃。完整操录音在点开通知后播放。
