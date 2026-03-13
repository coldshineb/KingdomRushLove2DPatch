.class Lcom/google/licensingservicehelper/LicensingServiceHelper$2;
.super Lcom/android/vending/licensing/ILicenseV2ResultListener$Stub;
.source "LicensingServiceHelper.java"


# annotations
.annotation system Ldalvik/annotation/EnclosingMethod;
    value = Lcom/google/licensingservicehelper/LicensingServiceHelper;->callLicensingService()V
.end annotation

.annotation system Ldalvik/annotation/InnerClass;
    accessFlags = 0x0
    name = null
.end annotation


# instance fields
.field final synthetic this$0:Lcom/google/licensingservicehelper/LicensingServiceHelper;


# direct methods
.method constructor <init>(Lcom/google/licensingservicehelper/LicensingServiceHelper;)V
    .locals 0

    iput-object p1, p0, Lcom/google/licensingservicehelper/LicensingServiceHelper$2;->this$0:Lcom/google/licensingservicehelper/LicensingServiceHelper;

    invoke-direct {p0}, Lcom/android/vending/licensing/ILicenseV2ResultListener$Stub;-><init>()V

    return-void
.end method


# virtual methods
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
