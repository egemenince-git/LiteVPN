# LiteVPN

[English](README.md) | [简体中文](README.zh-CN.md) | **Türkçe**

LiteVPN, macOS menü çubuğunda çalışan hafif bir OpenVPN ve WireGuard istemcisidir. Bu kişisel fork, [yzfly/LiteVPN](https://github.com/yzfly/LiteVPN) kaynak kodunu temel alır ve bağlantı ile trafik bilgilerini Vitals benzeri bir görünümde sunar.

## Öne çıkanlar

- Menü çubuğundan VPN’i bağlama ve kesme
- `.ovpn` dosyalarını içe aktarma; dosyayı pencereye sürükleme veya **Import** düğmesini kullanma
- WireGuard wg-quick profillerini (`.conf`, `.wg`, `.wgconf`) içe aktarma ve doğrulama
- OpenVPN ve WireGuard profillerini saklama, seçme, yeniden adlandırma ve silme; liste alfabetik sıralanır
- Bağlantı durumu, süre, gelen/giden toplam trafik ve canlı hız grafiği
- Canlı indirme ve yükleme hızları: uygun olduğunda Kbps, daha yüksek hızlarda Mbps
- VPN bağlantısı kurulduktan sonra genel IP adresini gösterme
- İsteğe bağlı girişte başlatma
- İngilizce ve Basitleştirilmiş Çince arayüz
- VPN tünelini macOS Network Extension sistem uzantısı içinde çalıştırma

Profil bilgileri yerel olarak kullanıcının `Application Support/LiteVPN/profiles.json` dosyasında tutulur. Bağlantı kurulunca genel IP önce `ifconfig.me`, gerekirse ipify hizmetlerinden alınır. Hız ve toplam trafik bilgileri tünel oturumunun sayaçlarından okunur.

## Gereksinimler ve sınırlar

- macOS 26 veya daha yenisi
- Xcode ve [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Mac App Store dışından imzalı dağıtım için Apple Developer Program üyeliği, Developer ID Application sertifikası ve Apple notarizasyonu

OpenVPN tarafında sertifika ve anahtarlar `.ovpn` dosyasının içine gömülü olmalıdır (`<ca>`, `<cert>`, `<key>`); kullanıcı adı/parola isteyen profiller reddedilir. WireGuard tarafında standart wg-quick alanları desteklenir; `PreUp` ve `PostUp` gibi özel komutlar desteklenmez.

İlk kullanımda macOS, LiteVPN sistem uzantısının etkinleştirilmesi için Sistem Ayarları’nda onay isteyebilir. Bu, VPN tünelini işletim sisteminin Network Extension altyapısına kurmak için gereken macOS onayıdır.

## Kaynak koddan derleme

XcodeGen ve Go’yu yükle (WireGuard motoru ilk derlemede Go modüllerini indirir):

```bash
brew install xcodegen
brew install go
```

Proje dosyasını üretip Debug derlemesi al:

```bash
xcodegen generate
xcodebuild -project LiteVPN.xcodeproj \
  -scheme LiteVPN \
  -configuration Debug \
  -derivedDataPath Build/DerivedData \
  build
```

Oluşan uygulama `Build/DerivedData/Build/Products/Debug/LiteVPN.app` altında bulunur. Bu fork, `com.egemenince` paket kimliklerini ve `99U7KZC748` Apple Developer takım kimliğini kullanır. Projeyi başka bir Apple hesabıyla imzalayacaksan `project.yml`, `App/AppConstants.swift` ve her iki entitlements dosyasındaki takım, paket ve App Group değerlerini kendi hesabına göre değiştir.

## Mac App Store dışından dağıtım

Dağıtım betiği arşiv oluşturur, Developer ID ile imzalar, Apple’a notarizasyon için gönderir, onay biletini uygulamaya ekler ve ZIP üretir. Sistem uzantısı, Apple’ın istediği gibi bundle kimliğiyle aynı ada sahip `.systemextension` paketi olarak gömülür. Betik arşivi notarizasyona göndermeden önce paket adını ve bundle kimliğini doğrular. Bu forkta kullanılan profil adları:

- Uygulama: `LiteVPN App Developer ID Local`
- Sistem uzantısı: `LiteVPN Tunnel Developer ID Local`
- `notarytool` Keychain profili: `LiteVPN-Notary`

Apple Developer portalında uygulama (`com.egemenince.LiteVPN`) ve tünel (`com.egemenince.LiteVPN.Tunnel`) App ID’leri için gerekli Network Extension izinlerini ve Developer ID provisioning profillerini ayarla. `notarytool` kimlik bilgisini parola komut satırında görünmeden Keychain’e kaydet:

```bash
xcrun notarytool store-credentials LiteVPN-Notary \
  --apple-id "APPLE_ID_ADRESIN" \
  --team-id 99U7KZC748
```

Komut uygulamaya özel Apple parolasını güvenli istemde sorar. Normal Apple hesabı parolanı kullanma ve parolayı kaynak koduna ekleme.

Ardından dağıtım paketini üret:

```bash
xcodegen generate
LITEVPN_APP_PROFILE="LiteVPN App Developer ID Local" \
LITEVPN_TUNNEL_PROFILE="LiteVPN Tunnel Developer ID Local" \
Scripts/release-direct.sh
```

Son ZIP `Build/DirectDistribution/` içine yazılır. ZIP’i kullanıcıya gönder; kullanıcı ZIP’i açıp `LiteVPN.app` dosyasını Uygulamalar klasörüne taşıyabilir. İlk açılışta macOS’un sistem uzantısı onayı isteyebileceğini belirt.

## Kaynak ve lisans

Bu fork, [yzfly/LiteVPN](https://github.com/yzfly/LiteVPN) projesinden türetilmiştir. OpenVPN için [TunnelKit](https://github.com/partout-io/tunnelkit), WireGuard için [resmi WireGuard Apple kaynak kodu](https://github.com/WireGuard/wireguard-apple) kullanılır. Kaynak proje GPL-3.0 lisanslıdır; üçüncü taraf lisansları depoda korunur.
