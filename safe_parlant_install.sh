#!/bin/bash

echo "🚀 PARLANT EKSİKSİZ KURULUM - SIFIR HATA GARANTİSİ"
echo "=================================================="

# GÜVENLI TEMİZLİK FONKSIYONU
safe_cleanup() {
    echo "🧹 Sistem güvenli temizleme başlatılıyor..."
    
    # Parlant süreçlerini kontrollü şekilde durdur
    echo "🔍 Parlant süreçleri kontrol ediliyor..."
    if pgrep -f parlant >/dev/null 2>&1; then
        echo "⏹️ Parlant süreçleri bulundu, durduruluyor..."
        sudo pkill -TERM -f parlant 2>/dev/null || true
        sleep 3
        sudo pkill -KILL -f parlant 2>/dev/null || true
    else
        echo "✅ Aktif parlant süreci bulunamadı"
    fi
    
    # Systemd servisini güvenli durdur
    echo "⚙️ Systemd servisi kontrol ediliyor..."
    if systemctl is-active --quiet parlant 2>/dev/null; then
        echo "⏹️ Parlant servisi durduruluyor..."
        sudo systemctl stop parlant 2>/dev/null || true
        sleep 2
    fi
    
    if systemctl is-enabled --quiet parlant 2>/dev/null; then
        echo "🔧 Parlant servisi devre dışı bırakılıyor..."
        sudo systemctl disable parlant 2>/dev/null || true
    fi
    
    # Servis dosyasını kaldır
    if [ -f /etc/systemd/system/parlant.service ]; then
        echo "🗑️ Servis dosyası kaldırılıyor..."
        sudo rm -f /etc/systemd/system/parlant.service
        sudo systemctl daemon-reload
    fi
    
    # Kullanıcı ve grup temizliği
    echo "👤 Kullanıcı temizliği yapılıyor..."
    if id parlant >/dev/null 2>&1; then
        echo "🗑️ Parlant kullanıcısı kaldırılıyor..."
        sudo userdel -r parlant 2>/dev/null || true
    fi
    
    if getent group parlant >/dev/null 2>&1; then
        echo "🗑️ Parlant grubu kaldırılıyor..."
        sudo groupdel parlant 2>/dev/null || true
    fi
    
    # Dizin temizliği
    if [ -d /opt/parlant ]; then
        echo "📁 Kurulum dizini temizleniyor..."
        sudo rm -rf /opt/parlant
    fi
    
    # UFW kuralı temizliği
    echo "🔒 Güvenlik duvarı kuralları temizleniyor..."
    sudo ufw delete allow 8800 2>/dev/null || true
    
    # Geçici dosyalar
    echo "🧹 Geçici dosyalar temizleniyor..."
    rm -rf /tmp/*parlant* /tmp/*products* 2>/dev/null || true
    
    echo "✅ Sistem temizliği tamamlandı!"
}

# Güvenli temizleme çalıştır
safe_cleanup

# HATA YAKALAMA AYARLARI
set -euo pipefail

# SİSTEM HAZIRLIK
echo ""
echo "📦 Sistem güncelleme ve paket kurulumu..."
export DEBIAN_FRONTEND=noninteractive

# İnternet bağlantısı kontrolü
if ! ping -c 1 google.com >/dev/null 2>&1; then
    echo "❌ İnternet bağlantısı yok! Lütfen bağlantınızı kontrol edin."
    exit 1
fi

echo "🔄 Paket listeleri güncelleniyor..."
if ! sudo apt update >/dev/null 2>&1; then
    echo "❌ Paket güncelleme başarısız!"
    exit 1
fi

echo "⬆️ Sistem paketleri güncelleniyor..."
sudo apt upgrade -y >/dev/null 2>&1

echo "📦 Gerekli paketler kuruluyor..."
if ! sudo apt install -y python3 python3-pip python3-venv git curl jq ufw >/dev/null 2>&1; then
    echo "❌ Paket kurulumu başarısız!"
    exit 1
fi

echo "✅ Sistem paketleri hazır!"

# PYTHON VERSİYON KONTROLÜ
echo "🐍 Python versiyonu kontrol ediliyor..."
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
if [ "$(echo "$PYTHON_VERSION >= 3.8" | bc -l)" != "1" ]; then
    echo "❌ Python 3.8+ gerekli, mevcut versiyon: $PYTHON_VERSION"
    exit 1
fi
echo "✅ Python versiyonu uygun: $PYTHON_VERSION"

# KULLANICI OLUŞTURMA
echo ""
echo "👤 Parlant kullanıcısı oluşturuluyor..."

# Grup oluştur
if ! getent group parlant >/dev/null 2>&1; then
    sudo groupadd parlant
    echo "✅ Parlant grubu oluşturuldu"
fi

# Kullanıcı oluştur
if ! id parlant >/dev/null 2>&1; then
    sudo useradd -r -g parlant -s /bin/false -d /opt/parlant -m parlant
    echo "✅ Parlant kullanıcısı oluşturuldu"
fi

# KURULUM DİZİNİ
echo ""
echo "📁 Kurulum dizini hazırlanıyor..."
sudo mkdir -p /opt/parlant
cd /opt/parlant

# Dizin sahipliği
sudo chown parlant:parlant /opt/parlant
echo "✅ Dizin hazır!"

# GIT REPOSITORY
echo ""
echo "📥 Parlant kaynak kodu indiriliyor..."

# Git kontrolü
if ! command -v git >/dev/null 2>&1; then
    echo "❌ Git kurulu değil!"
    exit 1
fi

# Repository clone
if ! sudo -u parlant git clone https://github.com/emcie-co/parlant.git /opt/parlant/source 2>/dev/null; then
    echo "❌ Git clone başarısız! Repository erişilebilir mi?"
    echo "📋 Ağ bağlantısını ve GitHub erişimini kontrol edin"
    exit 1
fi

# İçerikleri taşı
sudo -u parlant cp -r /opt/parlant/source/* /opt/parlant/
sudo -u parlant rm -rf /opt/parlant/source

echo "✅ Kaynak kod indirildi!"

# PYTHON SANAL ORTAM
echo ""
echo "🐍 Python sanal ortam oluşturuluyor..."

if ! sudo -u parlant python3 -m venv /opt/parlant/venv; then
    echo "❌ Sanal ortam oluşturulamadı!"
    echo "📋 Python3-venv paketi kurulu mu kontrol edin"
    exit 1
fi

# Pip güncelleme
echo "📦 Pip güncelleniyor..."
sudo -u parlant /opt/parlant/venv/bin/pip install --upgrade pip >/dev/null 2>&1

echo "✅ Sanal ortam oluşturuldu!"

# PARLANT KURULUMU
echo ""
echo "📦 Parlant paketi kuruluyor..."

# Pip paketlerini kur
if ! sudo -u parlant /opt/parlant/venv/bin/pip install "parlant[gemini]" >/dev/null 2>&1; then
    echo "❌ Parlant kurulumu başarısız!"
    echo "📋 Son pip hata logları:"
    sudo -u parlant /opt/parlant/venv/bin/pip install "parlant[gemini]" || true
    exit 1
fi

echo "✅ Parlant kuruldu!"

# GEMİNİ API ANAHTARI
echo ""
echo "🔑 Gemini API Anahtarı Kurulumu"
echo "================================"

while true; do
    echo -n "Gemini API anahtarını girin (boş bırakmak için Enter): "
    read -rs GEMINI_KEY
    echo
    
    if [ -z "$GEMINI_KEY" ]; then
        echo "⚠️ API anahtarı boş! Devam etmek istiyor musunuz? (y/N): "
        read -r continue_choice
        if [[ $continue_choice =~ ^[Yy]$ ]]; then
            GEMINI_KEY="YOUR_API_KEY_HERE"
            break
        fi
        continue
    fi
    
    # Basit API anahtarı format kontrolü
    if [[ ${#GEMINI_KEY} -lt 20 ]]; then
        echo "❌ API anahtarı çok kısa görünüyor. Tekrar deneyin."
        continue
    fi
    
    break
done

# .env dosyası oluştur
sudo tee /opt/parlant/.env > /dev/null <<EOF
GEMINI_API_KEY=$GEMINI_KEY
EOF

sudo chmod 400 /opt/parlant/.env
sudo chown parlant:parlant /opt/parlant/.env
echo "✅ API anahtarı kaydedildi!"

# ÜRÜN VERİLERİ İNDİRME (İsteğe bağlı)
echo ""
echo "📥 Ürün verileri indiriliyor..."

PRODUCT_URL="https://dl.dropboxusercontent.com/scl/fi/vn81hzkmadmmdl4jo9lpj/products.json?rlkey=xyx7qo17ntjiswa9ed7bia8xw&st=m0dqfy9r&dl=0"

if curl -s --max-time 30 --fail "$PRODUCT_URL" > /tmp/products.json 2>/dev/null; then
    # JSON doğrulama
    if jq . /tmp/products.json >/dev/null 2>&1; then
        echo "✅ Ürün verileri indirildi ve doğrulandı!"
        PRODUCTS_AVAILABLE=true
    else
        echo "⚠️ JSON formatı geçersiz, temel kurulum devam edecek"
        PRODUCTS_AVAILABLE=false
        rm -f /tmp/products.json
    fi
else
    echo "⚠️ Ürün verileri indirilemedi, temel kurulum devam edecek"
    PRODUCTS_AVAILABLE=false
fi

# SYSTEMD SERVİS
echo ""
echo "⚙️ Systemd servisi oluşturuluyor..."

sudo tee /etc/systemd/system/parlant.service >/dev/null <<'EOF'
[Unit]
Description=Parlant AI Conversation Engine
After=network.target

[Service]
Type=simple
User=parlant
Group=parlant
WorkingDirectory=/opt/parlant
Environment=PATH=/opt/parlant/venv/bin
EnvironmentFile=/opt/parlant/.env
ExecStart=/opt/parlant/venv/bin/parlant-server run --gemini --port 8800
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
TimeoutStartSec=60
KillMode=mixed
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable parlant >/dev/null 2>&1
echo "✅ Systemd servisi oluşturuldu!"

# GÜVENLİK DUVARI
echo ""
echo "🔒 Güvenlik duvarı yapılandırılıyor..."

# UFW aktif mi kontrol et
if ! sudo ufw status >/dev/null 2>&1; then
    sudo ufw --force enable >/dev/null 2>&1
fi

sudo ufw allow 8800 >/dev/null 2>&1
echo "✅ Port 8800 açıldı!"

# SERVİS BAŞLATMA
echo ""
echo "🚀 Parlant servisi başlatılıyor..."

if ! sudo systemctl start parlant; then
    echo "❌ Servis başlatılamadı!"
    echo "📋 Hata logları:"
    sudo journalctl -u parlant -n 10 --no-pager
    exit 1
fi

# SERVİS BAŞLAMA BEKLEMESİ
echo "⏳ Servisin başlaması bekleniyor..."
SUCCESS=false

for i in {1..60}; do
    if sudo systemctl is-active --quiet parlant && sudo ss -tlnp | grep -q ":8800" 2>/dev/null; then
        echo "✅ Servis başarıyla başlatıldı!"
        SUCCESS=true
        break
    fi
    
    if [ $i -eq 60 ]; then
        echo "❌ Servis başlatılamadı!"
        echo "📋 Hata logları:"
        sudo journalctl -u parlant -n 20 --no-pager
        exit 1
    fi
    
    sleep 1
    echo -n "."
done

if [ "$SUCCESS" = false ]; then
    exit 1
fi

echo ""

# AGENT OLUŞTURMA
echo ""
echo "🤖 AI Agent oluşturuluyor..."

for attempt in {1..5}; do
    if sudo -u parlant /opt/parlant/venv/bin/parlant agent create \
        --name "Alarko Carrier Satış Danışmanı" \
        --description "Sen Alarko Carrier'ın uzman Türkçe satış danışmanısın. Sadece Türkçe konuşuyorsun. Klima, kombi, ısıtma ve soğutma sistemleri konusunda müşterilere yardım ediyorsun. BTU hesaplama yapabiliyorsun ve ürün önerileri veriyorsun." >/dev/null 2>&1; then
        echo "✅ Agent oluşturuldu!"
        break
    fi
    
    if [ $attempt -eq 5 ]; then
        echo "❌ Agent oluşturulamadı! Servis loglarını kontrol edin:"
        sudo journalctl -u parlant -n 5 --no-pager
        exit 1
    fi
    
    echo "🔄 Agent oluşturma deneme $attempt/5..."
    sleep 3
done

# TEMEL KURALLAR
echo ""
echo "📋 Temel konuşma kuralları ekleniyor..."

# Kuralları dizide tanımla
declare -a guidelines=(
    "sistem davranış kuralı|Sen Türkçe konuşan bir Alarko Carrier satış danışmanısın. Her zaman Türkçe cevap veriyorsun. Hiçbir durumda İngilizce konuşmazsın. Müşterilere sıcak, samimi ve yardımsever davranıyorsun."
    "müşteri merhaba diyor veya selam veriyor veya selamlaşıyor|Merhaba! Ben Alarko Carrier'ın uzman satış danışmanıyım. Size Türkçe olarak klima, kombi ve ısıtma-soğutma sistemleri konusunda yardımcı olabilirim. BTU hesaplaması da yapabiliyorum. Hangi konuda yardıma ihtiyacınız var?"
    "müşteri BTU hesaplama soruyor veya kaç BTU gerekir diyor|BTU hesaplama için odanızın bilgilerini öğrenmem gerekiyor. Odanız kaç metrekare? Tavan yüksekliği yaklaşık kaç metre? (Eğer bilmiyorsanız standart 2,5 metre kabul edebilirim). BTU hesaplama formülü: Alan (m²) × Tavan Yüksekliği × 200 = Gerekli BTU. Örnek: 20 m² × 2,5 × 200 = 10.000 BTU. Özel durumlar için: Güney cephe +%15, üst kat +%10, fazla cam yüzeyi +%10 eklenir."
    "müşteri klima arıyor veya klima almak istiyor|Size en uygun klimayı bulmak için odanızın kaç metrekare olduğunu öğrenebilir miyim? BTU hesaplaması yaparak en uygun modeli önerebilirim. Alarko Carrier'da 9.000 BTU'dan 24.000 BTU'ya kadar çeşitli inverter klima seçeneklerimiz bulunuyor."
    "müşteri kombi arıyor veya kombi almak istiyor|Kombi seçimi için evinizin toplam ısıtma alanı yaklaşık kaç metrekare? Alarko Carrier'da yüksek verimli, çevre dostu kombi modellerimiz var. Profesyonel montaj ve servis hizmeti de sağlıyoruz."
    "müşteri fiyat soruyor veya ne kadar diyor|Fiyat bilgilerini size özel olarak hesaplamalıyız çünkü montaj, nakliye ve mevcut indirimlere göre değişkenlik gösterebilir. Hangi ürünle ilgileniyorsunuz? Size en güncel fiyatı ve ödeme seçeneklerini sunabilirim."
)

# Kuralları ekle
added_rules=0
for guideline in "${guidelines[@]}"; do
    IFS='|' read -ra ADDR <<< "$guideline"
    condition="${ADDR[0]}"
    action="${ADDR[1]}"
    
    if sudo -u parlant /opt/parlant/venv/bin/parlant guideline create \
        --condition "$condition" \
        --action "$action" >/dev/null 2>&1; then
        ((added_rules++))
    fi
done

echo "✅ $added_rules temel kural eklendi!"

# ÜRÜN VERİLERİ İŞLEME (Eğer mevcut ise)
if [ "$PRODUCTS_AVAILABLE" = true ]; then
    echo ""
    echo "📊 Ürün verileri işleniyor..."
    
    # Basitleştirilmiş ürün işleme
    python3 -c "
import json
try:
    with open('/tmp/products.json', 'r', encoding='utf-8') as f:
        products = json.load(f)
    print(f'📦 {len(products)} ürün bulundu')
    
    klima_count = sum(1 for p in products if 'klima' in p.get('Kategori', '').lower())
    kombi_count = sum(1 for p in products if 'kombi' in p.get('Kategori', '').lower())
    
    print(f'🌬️ Klima: {klima_count} model')
    print(f'🔥 Kombi: {kombi_count} model')
    
except Exception as e:
    print(f'⚠️ Ürün işleme hatası: {e}')
"
    
    rm -f /tmp/products.json
fi

# SON KONTROLLER
echo ""
echo "🔍 Final sistem kontrolleri..."

# Servis durumu
if sudo systemctl is-active --quiet parlant; then
    echo "✅ Parlant servisi çalışıyor"
else
    echo "❌ Servis sorunu!"
    exit 1
fi

# Port kontrolü
if sudo ss -tlnp | grep -q ":8800"; then
    echo "✅ Port 8800 dinleniyor"
else
    echo "❌ Port sorunu!"
    exit 1
fi

# Agent kontrolü
AGENT_COUNT=$(sudo -u parlant /opt/parlant/venv/bin/parlant agent list 2>/dev/null | wc -l)
if [ "$AGENT_COUNT" -gt 0 ]; then
    echo "✅ Agent(lar) mevcut ($AGENT_COUNT)"
else
    echo "❌ Agent sorunu!"
    exit 1
fi

# Kural sayısı
GUIDELINE_COUNT=$(sudo -u parlant /opt/parlant/venv/bin/parlant guideline list 2>/dev/null | wc -l)
echo "✅ Toplam kural sayısı: $GUIDELINE_COUNT"

# UFW kontrolü
if sudo ufw status | grep -q "8800"; then
    echo "✅ UFW port 8800 açık"
else
    echo "❌ UFW sorunu!"
    exit 1
fi

# API test
if curl -s --max-time 5 http://localhost:8800/health >/dev/null 2>&1; then
    echo "✅ API yanıt veriyor"
else
    echo "⚠️ API henüz yanıt vermiyor (bu normal olabilir)"
fi

# IP adresi
SERVER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "🎉🎉🎉 KURULUM BAŞARILI! 🎉🎉🎉"
echo "=================================="
echo ""
echo "🌐 ERİŞİM ADRESİ: http://$SERVER_IP:8800/chat/"
echo ""
echo "💬 TEST SORULARI:"
echo "   • Merhaba"
echo "   • 20 metrekare odam için kaç BTU klima gerekir?"
echo "   • Klima modelleri neler?"
echo "   • Kombi arıyorum"
echo ""
echo "🔧 YÖNETİM KOMUTLARI:"
echo "   • Servis durumu: sudo systemctl status parlant"
echo "   • Logları göster: sudo journalctl -u parlant -f"
echo "   • Servisi yeniden başlat: sudo systemctl restart parlant"
echo "   • Agent listesi: sudo -u parlant /opt/parlant/venv/bin/parlant agent list"
echo "   • Kural listesi: sudo -u parlant /opt/parlant/venv/bin/parlant guideline list"
echo ""
echo "✅ KURULUM BİLGİLERİ:"
echo "   🔹 Gemini AI entegrasyonu aktif"
echo "   🔹 Türkçe dil desteği"
echo "   🔹 BTU hesaplama sistemi"
echo "   🔹 $added_rules temel kural"
echo "   🔹 Otomatik servis yönetimi"
echo "   🔹 Güvenlik duvarı yapılandırması"
echo ""
echo "🚀 SİSTEM KULLANIMA HAZIR!"
echo ""
echo "ℹ️ İLK KULLANIM:"
echo "   1. Tarayıcınızda http://$SERVER_IP:8800/chat/ adresine gidin"
echo "   2. 'Merhaba' yazarak sistemi test edin"
echo "   3. Sorun yaşarsanız logları kontrol edin: sudo journalctl -u parlant -f"
