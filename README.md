# Harmony Authenticator 验证器

鸿蒙（HarmonyOS）单机版动态口令验证器，参照 Android 版
[Google Authenticator](https://github.com/google/google-authenticator-android) 移植实现，
采用 Material 3 风格 UI。

- **bundleName**: `com.razor.tools.authenticator`
- 完全离线：无网络权限、无任何依赖库，数据仅存本机（preferences）

## 功能

- **TOTP**（RFC 6238，30/60 秒周期）与 **HOTP**（RFC 4226，计数器）
- 算法：HMAC-SHA1 / HMAC-SHA256；位数 6 / 8
- 验证码每 250ms 刷新，卡片带倒计时圆环（剩余 <5 秒变色提醒）
- 点击卡片复制验证码；HOTP 点“下一个”按钮递增计数器
- 长按卡片：复制 / 上移 / 下移 / 重命名 / 删除
- 添加账户：手动输入 或 粘贴 `otpauth://` 链接导入（自动解析回填表单）
- 添加页实时预览当前验证码
- 深色 / 浅色主题跟随系统

## OTP 核心与 Android 版的对应关系

| 本工程 (ArkTS) | google-authenticator-android (Java) |
| --- | --- |
| `otp/Digest.ets`（SHA1/SHA256/HMAC） | `PasscodeGenerator` + JCE `Mac` |
| `otp/Base32.ets` | `util/Base32String.java` |
| `otp/OtpEngine.ets` | `otp/OtpProvider.java` / `TotpCounter` |
| `otp/OtpUri.ets` | `otpauth://` URI 解析（散见于各 Activity） |
| `store/AccountStore.ets` | `otp/AccountDb.java`（SQLite → preferences+JSON） |

为避免异步 crypto 框架带来的每秒刷新开销，摘要/HMAC 为纯 ArkTS 同步实现，
已通过 RFC 4226 / RFC 6238 / RFC 2202 官方测试向量验证（见 `tools/test_otp.js`）。

## 构建

DevEco Studio 6.1+（HarmonyOS SDK，compileSdk 6.1.1(24) / compatible 6.0.2(22)）。

命令行（Windows 示例，SDK 目录需含版本子目录）：

```bash
# 一次性：构造 hvigor 期望的 SDK 目录结构
powershell New-Item -ItemType Junction -Path C:\Users\<you>\hvigor-sdk\HarmonyOS-6.1.1 `
  -Target "C:\Program Files\Huawei\DevEco Studio\sdk\default"

export DEVECO_SDK_HOME=/c/Users/<you>/hvigor-sdk
node "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" \
  assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`（未签名）。
安装前请在 DevEco Studio 中 **File → Project Structure → Signing Configs** 勾选
Automatically generate signature 完成自动签名，再运行到设备/模拟器。

## 测试

```bash
node tools/test_otp.js
```

覆盖：Base32 容错解码、HOTP RFC4226 十组向量、TOTP RFC6238 六组向量、
SHA1/SHA256 摘要、HMAC RFC2202、与 Node crypto 随机交叉对比（含边界密钥长度、
跨分组长消息、64 位状态编码）。

## 目录结构

```
AppScope/                     应用级配置（bundleName、图标、多语言应用名）
entry/src/main/ets/
  entryability/EntryAbility   入口：初始化存储、深浅色同步
  model/Account.ets           账户数据模型
  otp/                        OTP 核心（Digest/Base32/OtpEngine/OtpUri）
  store/AccountStore.ets      持久化（preferences + JSON）
  common/Theme.ets            Material 3 色板（深浅色）
  components/                 AccountCard / CountdownRing / SegmentedButtons / EmptyView
  pages/Index.ets             主页（列表/复制/长按菜单/FAB）
  pages/AddAccount.ets        添加账户（手动输入 / 链接导入）
tools/                        图标生成、RFC 向量测试脚本
```
