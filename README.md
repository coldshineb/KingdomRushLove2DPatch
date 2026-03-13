# Kingdom Rush 王国保卫战 Love2D 引擎 Android 版修补指南
本指南适用于王国保卫战、前线、起源、联盟这 4 款使用 Love2D 引擎开发的作品

本指南旨在对 Android 版进行修补，以实现与 PC 版相同的游戏体验，本仓库的示例代码基于联盟 7.00.56

本指南出于个人对数字内容的收藏需要制作，因移动端游戏向来有各种内购、广告满天飞、常年不更新游戏内容只更新氪金内容的毛病，本人已对许多经典游戏如割绳子、水果忍者、暗影格斗等制作了具有纪念收藏价值的完美版，一般情况下会对原安装包进行去签名验证、去授权验证、去广告、存档注入（如割绳子某款中的体力限制解除、无限付费道具等）、删除通知权限，避免不良体验，请务必在使用本指南时秉承相同的理念，即使联盟的 DLC、英雄等售价再逆天，也切勿跳脸正版玩家造成社区不良风气

## 授权验证修补

修改位于 `com/google/licensingservicehelper/LicensingServiceHelper$2` 下的 `public verifyLicense(ILandroid/os/Bundle;)V` 方法，伪造返回给底层授权的字符串，使得购买的正版游戏可以在任意设备上运行

联盟使用新版 LVL
```
.method public verifyLicense(ILandroid/os/Bundle;)V
    .locals 1

    const-string p1, "LICENSE_DATA"
    invoke-virtual {p2, p1}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;
    move-result-object p1

    if-nez p1, :cond_0

    const-string p1, "{\"iat\":0,\"appSpecificUserId\":\"bypassed\",\"packageName\":\"bypassed\"}"

    :cond_0
    const-string p2, "bypassed_license"
    iget-object v0, p0, Lcom/google/licensingservicehelper/LicensingServiceHelper$2;->this$0:Lcom/google/licensingservicehelper/LicensingServiceHelper;
    invoke-static {v0}, Lcom/google/licensingservicehelper/LicensingServiceHelper;->access$400(Lcom/google/licensingservicehelper/LicensingServiceHelper;)Lcom/google/licensingservicehelper/LicensingServiceCallback;

    move-result-object v0

    invoke-interface {v0, p1, p2}, Lcom/google/licensingservicehelper/LicensingServiceCallback;->allow(Ljava/lang/String;Ljava/lang/String;)V

    return-void
.end method
```

王国保卫战、前线、起源使用旧版 LVL
```
.method public verifyLicense(ILandroid/os/Bundle;)V
    .registers 3

    iget-object v0, p0, Lcom/google/licensingservicehelper/LicensingServiceHelper$2;->this$0:Lcom/google/licensingservicehelper/LicensingServiceHelper;
    invoke-static {v0}, Lcom/google/licensingservicehelper/LicensingServiceHelper;->access$400(Lcom/google/licensingservicehelper/LicensingServiceHelper;)Lcom/google/licensingservicehelper/LicensingServiceCallback;
    move-result-object v0

    const-string v1, "bypassed"

    invoke-interface {v0, v1}, Lcom/google/licensingservicehelper/LicensingServiceCallback;->allow(Ljava/lang/String;)V

    return-void
.end method
```

## 内购与内容解锁修补

本方案修改了底层 Love2D (LuaJIT) 引擎的核心计费脚本 `platform_services_gpiab.lua`，本脚本需要使用 luajit-decompiler-v2 等工具解密为可读文本后编辑，因 Love2D 引擎支持同时读取已编译和未编译的脚本，因此无需在修改后考虑回编译问题

### 修补流程

**1. 拦截内购请求**

* 拦截 `purchase_product(id)`，不再调用 Java 层 `jnia` 发起网络请求

**2. 零秒发货**

原版引擎每 3 秒才轮询一次发货车间（`late_update`）。设为 0 后，引擎会在 UI 转圈的下一帧瞬间执行发货逻辑，并立刻抛出 `SGN_PS_PURCHASE_PRODUCT_FINISHED` 成功信号

* 将顶部配置 `iab.update_interval` 和 `iab.late_update_delay` 设为 `0`

**3. 禁止内购刷新**

为了禁止游戏在启动时从 Google 获取内购信息，导致先前解锁的内购项目回锁

* 重写 `sync_purchases()` 和 `late_update()` 里的发货流程。强制遍历内存中的 `purchases_cache`，分类写入本地 `storage:load_global()` 并直接存盘。每次开局验证时，只读本地明文存档

**4. 离线价格标签**

为了让游戏能够在没有 GMS 框架的设备上完美运行，需要删除内购价格获取相关代码

* 重写 `sync_products()`，直接从本地 `remote_config` 提取商品 ID，并强行打上 `Free` 的价格标签，确保商店按钮永远为可点击状态

**5. Play Pass 订阅欺骗**

当设备上存在拥有 Play Pass 订阅的账号时，游戏会自动关闭所有弹出式广告、解锁全部 DLC、英雄、塔，并删除钻石内购，实现与 PC 版一致的游戏体验

* 强制 `is_premium()` 返回 `true`，并在 `init` 结尾声明 `self.premium = true`

若只想要内购破解，不需要进行此步骤，或者可选将 `is_premium()` 的返回值改为 `return false`，这样即使设备上有 Play Pass 订阅也可继续使用内购破解

# 打包指南
* **合包：** 如果下载的是未经修改的纯原版游戏，可能拿到的是 apks 这种分包，使用 `java -jar APKEditor.jar m -i .\xxx.apks -o xxx.apk -extractNativeLibs true` 合包
* **解包：** 使用 `apktool d xxx.apk` 将基础包和所有 config 分包全部解开为明文
* **移除授权验证：** 将修改好的 `LicensingServiceHelper$2.smali` 复制到解包目录下的 `smali_classesX/com/google/licensingservicehelper/`
* **替换引擎核心：** 将修改好的 `platform_services_gpiab.lua` 到解包目录下的 `assets/gc64/all-phone/` 和 `assets/gc32/all-phone/`
* **重编译与对齐签名：** 使用 `apktool b xxx -o xxx_patched.apk` 重新构建 APK，最后使用 `java -jar .\uber-apk-signer.jar -a xxx_patched.apk` 进行 V1/V2/V3 签名及 ZipAlign 对齐
