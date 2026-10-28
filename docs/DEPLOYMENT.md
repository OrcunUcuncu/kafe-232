# Kontrollü IIS yayını

Bu proje klasik ASP.NET MVC 5 / .NET Framework 4.8.1 uygulamasıdır. CI, NuGet restore, Release derlemesi, Razor doğrulaması ve yayın paketi üretir. Henüz bulunmayan EF6/EDMX entegrasyonunu veya kafe işlevlerini test etmiş sayılmaz.

## İlk aşamanın sınırı

- Derleme GitHub-hosted Windows ortamında yapılır. Genel uygulama reposuna bağlı bir self-hosted runner sunucuya kurulmaz.
- İlk CD adımı, yöneticinin seçtiği ve onayladığı CI artifact'ının aşağıdaki betikle IIS'e alınmasıdır. Bu aşama insan tarafından başlatılır; otomatik GitHub onaylı uzak yayın bağlantısı hazırmış gibi değerlendirilmez.
- Sunucu yalnız yönetici tarafından hazırlanır. Geliştiricilere RDP/admin yetkisi verilmesi gerekmez.
- `KafeDemo` sitesi ve aynı adlı uygulama havuzu önceden hazırlanmış olmalıdır. Başlangıç adresi `http://127.0.0.1:8080/` olup internet erişimi sağlamaz. Özel ağ/VPN bağlantısı ve gerekli GitHub yayın yetkileri tamamlanana kadar CD uzaktan otomatik değildir.
- Windows Authentication açık, Anonymous Authentication kapalı kalır. Havuz `ApplicationPoolIdentity` ve .NET `v4.0` kullanır; uygulama Administrator/sysadmin olarak çalıştırılmaz.
- Başlangıç klasörü `C:\KafeDemo\releases\bootstrap` boş olabilir. İlk başarılı yayından önce geri dönebilecek doğrulanmış uygulama sürümü yoktur.

## Yöneticinin onayladığı paketi alma

1. GitHub Actions'ta doğru uygulama reposunun CI çalışmasını açın.
2. Yayın adayı için `main` dalındaki başarılı çalışmayı ve 40 karakterlik commit SHA'sını kontrol edin. Bir PR/fork çalışmasını veya başka bir kişinin gönderdiği ZIP'i yayın adayı olarak kullanmayın.
3. O çalışmanın yayın artifact'ını indirin ve sunucuda ayrı bir geçici klasöre çıkarın. Paket kökünde `Web.config`, `bin`, `Views` ve `deployment-manifest.json` bulunmalıdır.
4. Aşağıdaki komutlarda `C:\OnaylananPaket` ve `<onaylanan-40-karakterlik-sha>` alanlarını gerçek değerlerle değiştirin. Manifest etiketleri ve SHA256 envanteri paketin bozulmasını tespit eder; tek başına bir dijital imza veya GitHub kaynağının kanıtı değildir. Kaynağın ve onaylanan commit'in yukarıdaki adımla kontrolü gerekir.

## Önce paketi doğrulama

Yükseltilmiş yetki veya IIS değişikliği gerektirmez:

```powershell
.\scripts\Deploy-Iis.ps1 -PackageDirectory 'C:\OnaylananPaket' `
  -ExpectedCommitSha '<onaylanan-40-karakterlik-sha>' -ValidateOnly
```

`-WhatIf` de dosyaları doğrular, ardından yapılacak işlemi bildirir; IIS'e dosya kopyalamaz veya siteyi değiştirmez.

Manifest'te `sourceDirty` ve `validationOnly` açık boolean değerler olmalıdır. Her ikisi de `false` olmayan paket yayınlanamaz. `Build-Package.ps1 -AllowDirtySourceForValidation` ile yerel doğrulama için hazırlanmış bir paket, `-ValidateOnly` kontrolünde incelenebilir ve `Deployable=False` döndürür; gerçek yayın ve `-WhatIf` bu paketi reddeder. Manifest commit etiketi, değiştirilmiş yerel kaynakların temiz bir commit'e aitmiş gibi gösterilmesi için kullanılamaz.

## IIS yayını

Sunucuda yönetici olarak **Windows PowerShell 5.1** (`powershell.exe`) açın. PowerShell 7 yerine 5.1, Windows'un IIS WebAdministration modülü için kullanılır.

```powershell
.\scripts\Deploy-Iis.ps1 -PackageDirectory 'C:\OnaylananPaket' `
  -ExpectedCommitSha '<onaylanan-40-karakterlik-sha>'
```

Betik şunları yapar:

1. Repository (`OrcunUcuncu/kafe-232`), framework (`net481`), onaylanan commit, eksiksiz dosya envanteri, boyut ve SHA256 özetlerini doğrular. Eklenmiş/eksilmiş dosyaları, yol taşmasını, junction/symlink'leri ve veritabanı/anahtar dosyalarını reddeder.
2. Aynı anda ikinci yayın veya geri dönüşe izin vermeyen dosya kilidi alır.
3. Paketi yeni bir `C:\KafeDemo\releases\<sürüm>` klasörüne kopyalar. Önceki sürümleri silmez. Uygulama havuzuna kod üzerinde yalnız okuma/çalıştırma izni verir.
4. IIS'in fiziksel yolunu yeni sürüme geçirir ve yalnız bu siteye ayrılmış havuzu yeniden başlatır.
5. Smoke adresinin seçilen sitenin açıkça tanımlı loopback bağlamasıyla eşleştiğini doğrular. Yerelde mevcut Windows kullanıcısıyla HTTP 200, anonim istekle HTTP 401 bekler. Bu basit kontrol uygulamanın tüm iş kurallarını test etmez. Yönetici hesabı, sitenin erişim listesinde izinli olmalıdır.
6. Kontrol başarılıysa `C:\KafeDemo\deployment-state.json` kaydını atomik olarak günceller. Başarısızsa eski fiziksel yolu geri yükler ve işlemi başarısız bildirir. İlk yayında eski yol boş bootstrap olabilir; bunun geri yüklenmesi çalışan bir önceki uygulama bulunduğu anlamına gelmez.

Sunucu yöneticisi `C:\KafeDemo` kökünün ve durum/kilit dosyalarının yalnız SYSTEM/Administrators tarafından yazılabildiğini korumalıdır. Uygulama havuzu bu dosyalara yazamamalıdır. Gelecekte dosya yükleme/log ihtiyacı çıkarsa kod klasörüne yazma açmak yerine repo dışı ayrı veri klasörü planlanır.

## Önceki uygulama sürümüne dönüş

Durum dosyasındaki `previousRelease.commitSha` değerini kontrol edin ve geri dönülecek SHA'yı açıkça verin:

```powershell
.\scripts\Rollback-Iis.ps1 -ExpectedCommitSha '<onceki-40-karakterlik-sha>' -ValidateOnly
.\scripts\Rollback-Iis.ps1 -ExpectedCommitSha '<onceki-40-karakterlik-sha>'
```

Geri dönüş de paket bütünlüğünü ve HTTP 200/401 kontrollerini çalıştırır. Mevcut IIS yolu kayıtlı durumla uyuşmuyorsa betik durur; beklenmeyen bir site değişikliğinin üzerine yazmaz. İlk başarılı yayında önceki doğrulanmış uygulama olmadığı için normal geri dönüş yapılamaz. Yayınlar ve geri dönüşler eski sürüm klasörlerini silmez.

## Veritabanı ayrı yönetilir

Bu betikler SQL bağlantısı açmaz; veritabanı oluşturmaz, migration/seed/reset/restore veya `CREATE`, `DROP`, `TRUNCATE` çalıştırmaz. Repodaki mevcut SQL dosyaları her yayında tekrar yürütülmez. Kod sürümüne dönüş, veritabanı şemasını geri almaz. EF Database First şema değişikliği, gerçek EDMX güncellemesi, test ve yedek/geri dönüş planı ayrı onaylı iştir.

Windows kullanıcılarının uygulamadaki `Employee.WindowsLogin` eşlemesi de yayın betiğinin görevi değildir. Henüz olmayan Employee/Manager veya başka bir entity/veri bu süreçte oluşturulmaz.
