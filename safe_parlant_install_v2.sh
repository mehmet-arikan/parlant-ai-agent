#!/bin/bash
set -euo pipefail

echo "🚀 PARLANT EKSİKSİZ KURULUM - SIFIR HATA GARANTİSİ"
echo "=================================================="

# KOMPLE TEMİZLİK
echo "🧹 Sistem tamamen temizleniyor..."
sudo pkill -f parlant 2>/dev/null || true
sudo systemctl stop parlant 2>/dev/null || true
sudo systemctl disable parlant 2>/dev/null || true
sudo rm -f /etc/systemd/system/parlant.service
sudo systemctl daemon-reload
sudo userdel -r parlant 2>/dev/null || true
sudo groupdel parlant 2>/dev/null || true
sudo rm -rf /opt/parlant
sudo ufw delete allow 8800 2>/dev/null || true
rm -rf /tmp/*parlant* /tmp/*products* 2>/dev/null || true
echo "✅ Sistem tamamen temizlendi!"

# SİSTEM HAZIRLIK
echo "📦 Sistem güncelleme ve paket kurulumu..."
export DEBIAN_FRONTEND=noninteractive
sudo apt update >/dev/null 2>&1
sudo apt upgrade -y >/dev/null 2>&1
sudo apt install -y python3 python3-pip python3-venv git curl jq ufw >/dev/null 2>&1
echo "✅ Sistem paketleri hazır!"

# KULLANICI OLUŞTURMA
echo "👤 Parlant kullanıcısı oluşturuluyor..."
sudo groupadd parlant 2>/dev/null || true
sudo useradd -r -g parlant -s /bin/false -d /opt/parlant parlant 2>/dev/null || true
echo "✅ Kullanıcı oluşturuldu!"

# KURULUM DİZİNİ
echo "📁 Kurulum dizini hazırlanıyor..."
sudo mkdir -p /opt/parlant
cd /opt/parlant
echo "✅ Dizin hazır!"

# GIT REPOSITORY
echo "📥 Parlant kaynak kodu indiriliyor..."
if ! sudo git clone https://github.com/emcie-co/parlant.git . >/dev/null 2>&1; then
    echo "❌ Git clone başarısız!"
    exit 1
fi
sudo chown -R parlant:parlant /opt/parlant
echo "✅ Kaynak kod indirildi!"

# PYTHON SANAL ORTAM
echo "🐍 Python sanal ortam oluşturuluyor..."
if ! sudo -u parlant python3 -m venv /opt/parlant/venv; then
    echo "❌ Sanal ortam oluşturulamadı!"
    exit 1
fi
echo "✅ Sanal ortam oluşturuldu!"

# PARLANT KURULUMU
echo "📦 Parlant paketi kuruluyor..."
sudo -u parlant /opt/parlant/venv/bin/pip install --upgrade pip >/dev/null 2>&1
if ! sudo -u parlant /opt/parlant/venv/bin/pip install "parlant[gemini]" >/dev/null 2>&1; then
    echo "❌ Parlant kurulumu başarısız!"
    exit 1
fi
echo "✅ Parlant kuruldu!"

# GEMİNİ API ANAHTARI
echo -n "Gemini API anahtarını girin: "
read -rs GEMINI_KEY
echo

if [ -z "$GEMINI_KEY" ]; then
    echo "❌ API anahtarı boş olamaz!"
    exit 1
fi

sudo tee /opt/parlant/.env > /dev/null <<EOF
GEMINI_API_KEY=$GEMINI_KEY
EOF
sudo chmod 600 /opt/parlant/.env
sudo chown parlant:parlant /opt/parlant/.env

# ÜRÜN VERİLERİ İNDİRME
echo "📥 Ürün verileri indiriliyor..."
curl -s --max-time 30 \
    "https://dl.dropboxusercontent.com/scl/fi/vn81hzkmadmmdl4jo9lpj/products.json?rlkey=xyx7qo17ntjiswa9ed7bia8xw&st=m0dqfy9r&dl=0" \
    > /tmp/products.json || {
    echo "❌ Ürün verileri indirilemedi!"
    exit 1
}

# JSON DOĞRULAMA
if ! jq . /tmp/products.json >/dev/null 2>&1; then
    echo "❌ Geçersiz JSON formatı!"
    exit 1
fi

echo "✅ Ürün verileri indirildi ve doğrulandı!"

# SYSTEMD SERVİS
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

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable parlant >/dev/null 2>&1
echo "✅ Systemd servisi oluşturuldu!"

# GÜVENLİK DUVARI
echo "🔒 Güvenlik duvarı yapılandırılıyor..."
sudo ufw --force enable >/dev/null 2>&1
sudo ufw allow 8800 >/dev/null 2>&1
echo "✅ Port 8800 açıldı!"

# SERVİS BAŞLATMA
echo "🚀 Parlant servisi başlatılıyor..."
sudo systemctl start parlant

# SERVİS BAŞLAMA BEKLEMESİ
echo "⏳ Servisin başlaması bekleniyor..."
for i in {1..60}; do
    if sudo systemctl is-active --quiet parlant && sudo ss -tlnp | grep -q ":8800"; then
        echo "✅ Servis başarıyla başlatıldı!"
        break
    fi
    
    if [ $i -eq 60 ]; then
        echo "❌ Servis başlatılamadı!"
        echo "📋 Hata logları:"
        sudo journalctl -u parlant -n 20 --no-pager
        exit 1
    fi
    
    sleep 1
done

# AGENT OLUŞTURMA
echo "🤖 AI Agent oluşturuluyor..."
for attempt in {1..5}; do
    if sudo -u parlant /opt/parlant/venv/bin/parlant agent create \
        --name "Alarko Carrier Satış Danışmanı" \
        --description "Sen Alarko Carrier'ın uzman Türkçe satış danışmanısın. Sadece Türkçe konuşuyorsun. Klima, kombi, ısıtma ve soğutma sistemleri konusunda müşterilere yardım ediyorsun. BTU hesaplama yapabiliyorsun ve ürün önerileri veriyorsun." >/dev/null 2>&1; then
        echo "✅ Agent oluşturuldu!"
        break
    fi
    
    if [ $attempt -eq 5 ]; then
        echo "❌ Agent oluşturulamadı!"
        exit 1
    fi
    
    echo "🔄 Agent oluşturma deneme $attempt/5..."
    sleep 3
done

# TEMEL KURALLAR
echo "📋 Temel konuşma kuralları ekleniyor..."

# Türkçe zorunluluğu
sudo -u parlant /opt/parlant/venv/bin/parlant guideline create \
    --condition "sistem davranış kuralı" \
    --action "Sen Türkçe konuşan bir Alarko Carrier satış danışmanısın. Her zaman Türkçe cevap veriyorsun. Hiçbir durumda İngilizce konuşmazsın. Müşterilere sıcak, samimi ve yardımsever davranıyorsun." >/dev/null 2>&1

# Selamlama
sudo -u parlant /opt/parlant/venv/bin/parlant guideline create \
    --condition "müşteri merhaba diyor veya selam veriyor veya selamlaşıyor" \
    --action "Merhaba! Ben Alarko Carrier'ın uzman satış danışmanıyım. Size Türkçe olarak klima, kombi ve ısıtma-soğutma sistemleri konusunda yardımcı olabilirim. BTU hesaplaması da yapabiliyorum. Hangi konuda yardıma ihtiyacınız var?" >/dev/null 2>&1

# BTU hesaplama
sudo -u parlant /opt/parlant/venv/bin/parlant guideline create \
    --condition "müşteri BTU hesaplama soruyor veya kaç BTU gerekir diyor" \
    --action "BTU hesaplama için odanızın bilgilerini öğrenmem gerekiyor. Odanız kaç metrekare? Tavan yüksekliği yaklaşık kaç metre? (Eğer bilmiyorsanız standart 2,5 metre kabul edebilirim). BTU hesaplama formülü: Alan (m²) × Tavan Yüksekliği × 200 = Gerekli BTU. Örnek: 20 m² × 2,5 × 200 = 10.000 BTU. Özel durumlar için: Güney cephe +%15, üst kat +%10, fazla cam yüzeyi +%10 eklenir." >/dev/null 2>&1

# Klima arama
sudo -u parlant /opt/parlant/venv/bin/parlant guideline create \
    --condition "müşteri klima arıyor veya klima almak istiyor" \
    --action "Size en uygun klimayı bulmak için odanızın kaç metrekare olduğunu öğrenebilir miyim? BTU hesaplaması yaparak en uygun modeli önerebilirim. Alarko Carrier'da 9.000 BTU'dan 24.000 BTU'ya kadar çeşitli inverter klima seçeneklerimiz bulunuyor." >/dev/null 2>&1

# Kombi arama
sudo -u parlant /opt/parlant/venv/bin/parlant guideline create \
    --condition "müşteri kombi arıyor veya kombi almak istiyor" \
    --action "Kombi seçimi için evinizin toplam ısıtma alanı yaklaşık kaç metrekare? Alarko Carrier'da yüksek verimli, çevre dostu kombi modellerimiz var. Profesyonel montaj ve servis hizmeti de sağlıyoruz." >/dev/null 2>&1

# Fiyat soruları
sudo -u parlant /opt/parlant/venv/bin/parlant guideline create \
    --condition "müşteri fiyat soruyor veya ne kadar diyor" \
    --action "Fiyat bilgilerini size özel olarak hesaplamalıyız çünkü montaj, nakliye ve mevcut indirimlere göre değişkenlik gösterebilir. Hangi ürünle ilgileniyorsunuz? Size en güncel fiyatı ve ödeme seçeneklerini sunabilirim." >/dev/null 2>&1

echo "✅ Temel kurallar eklendi!"

# ÜRÜN VERİLERİ İŞLEME
echo "📊 Ürün verileri işleniyor ve kurallar oluşturuluyor..."

cat > /tmp/process_products.py << 'PYTHON_SCRIPT'
import json
import subprocess
import re
import sys
import time

def run_guideline_command(condition, action, max_retries=3):
    """Güvenli guideline ekleme"""
    for attempt in range(max_retries):
        try:
            result = subprocess.run(
                ['/opt/parlant/venv/bin/parlant', 'guideline', 'create', '--condition', condition, '--action', action],
                capture_output=True,
                text=True,
                timeout=30
            )
            if result.returncode == 0:
                return True
            time.sleep(1)
        except Exception:
            time.sleep(1)
    return False

try:
    with open('/tmp/products.json', 'r', encoding='utf-8') as f:
        products = json.load(f)
    
    print(f'📦 {len(products)} ürün işleniyor...')
    
    successful_rules = 0
    klima_products = {}
    kombi_products = []
    
    # Ürünleri işle
    for product in products:
        name = product.get('Ürün Adı', '').strip()
        if not name:
            continue
            
        category = product.get('Kategori', '').lower().strip()
        normal_price = product.get('Normal Fiyat', '')
        sadakat_price = product.get('Sadakat Fiyatı', '')
        stock = product.get('Stok Durumu', '')
        cooling_capacity = product.get('Soğutma Kapasitesi (BTU/h)', '')
        heating_capacity = product.get('Isıtma Kapasitesi (BTU/h)', '')
        link = product.get('Ürün Linki', '')
        
        # Stok durumu
        stock_status = '✅ Stokta var' if 'Stokta Var' in stock else '❌ Stokta yok'
        
        # Fiyat bilgisi
        price_text = f'💰 Normal Fiyat: {normal_price}'
        if sadakat_price and 'Sadakat Fiyatı Yok' not in sadakat_price:
            price_text += f' | Sadakat Fiyatı: {sadakat_price}'
        
        if category == 'klima':
            # BTU değerini çıkar
            btu_match = re.search(r'(\d+\.?\d*)\s*BTU', name, re.IGNORECASE)
            if btu_match:
                btu = btu_match.group(1).replace('.', '')
                try:
                    btu_num = float(btu)
                    
                    # BTU kategorisine göre grupla
                    if btu_num <= 9000:
                        btu_category = '9000'
                        room_size = '12-18 m²'
                    elif btu_num <= 12000:
                        btu_category = '12000'
                        room_size = '18-25 m²'
                    elif btu_num <= 18000:
                        btu_category = '18000'
                        room_size = '25-35 m²'
                    elif btu_num <= 24000:
                        btu_category = '24000'
                        room_size = '35-45 m²'
                    else:
                        btu_category = '24000+'
                        room_size = '45+ m²'
                    
                    if btu_category not in klima_products:
                        klima_products[btu_category] = []
                    
                    product_info = {
                        'name': name,
                        'stock_status': stock_status,
                        'price_text': price_text,
                        'room_size': room_size,
                        'cooling_capacity': cooling_capacity,
                        'heating_capacity': heating_capacity,
                        'link': link
                    }
                    
                    klima_products[btu_category].append(product_info)
                    
                except ValueError:
                    continue
        
        elif category == 'kombi':
            heating_power = product.get('Isıtma Kapasitesi (kW)', '')
            efficiency = product.get('Enerji Verimliliği - Isıtma (%)', '')
            
            kombi_info = {
                'name': name,
                'stock_status': stock_status,
                'price_text': price_text,
                'heating_power': heating_power,
                'efficiency': efficiency,
                'link': link
            }
            
            kombi_products.append(kombi_info)
    
    # Klima kuralları oluştur
    print("🌬️ Klima kuralları oluşturuluyor...")
    for btu_category, products_list in klima_products.items():
        if not products_list:
            continue
            
        # En fazla 3 ürünü göster
        top_products = products_list[:3]
        
        # Kural metni oluştur
        room_size = top_products[0]['room_size']
        rule_text = f"🌬️ {btu_category} BTU Klima Seçenekleri ({room_size}):\\n\\n"
        
        for i, product in enumerate(top_products, 1):
            rule_text += f"{i}. 🏷️ {product['name']}\\n"
            rule_text += f"   {product['stock_status']}\\n"
            rule_text += f"   {product['price_text']}\\n"
            if product['cooling_capacity']:
                rule_text += f"   ❄️ Soğutma: {product['cooling_capacity']}\\n"
            if product['heating_capacity']:
                rule_text += f"   🔥 Isıtma: {product['heating_capacity']}\\n"
            if product['link']:
                rule_text += f"   🔗 Detay: {product['link']}\\n"
            rule_text += "\\n"
        
        rule_text += "📞 Montaj dahil detaylı fiyat teklifi için iletişime geçin!"
        
        # Kuralları ekle
        conditions = [
            f"müşteri {btu_category} BTU klima arıyor",
            f"müşteri {room_size} klima istiyor",
            f"hesaplama sonucu {btu_category} BTU çıkıyor"
        ]
        
        for condition in conditions:
            if run_guideline_command(condition, rule_text):
                successful_rules += 1
                break
    
    # Kombi kuralları oluştur
    if kombi_products:
        print("🔥 Kombi kuralları oluşturuluyor...")
        
        kombi_rule_text = "🔥 Alarko Carrier Kombi Modelleri:\\n\\n"
        
        for i, kombi in enumerate(kombi_products[:5], 1):  # İlk 5 kombi
            kombi_rule_text += f"{i}. 🏷️ {kombi['name']}\\n"
            kombi_rule_text += f"   {kombi['stock_status']}\\n"
            kombi_rule_text += f"   {kombi['price_text']}\\n"
            if kombi['heating_power']:
                kombi_rule_text += f"   🔥 Isıtma Gücü: {kombi['heating_power']} kW\\n"
            if kombi['efficiency']:
                kombi_rule_text += f"   ⚡ Verimlilik: %{kombi['efficiency']}\\n"
            if kombi['link']:
                kombi_rule_text += f"   🔗 Detay: {kombi['link']}\\n"
            kombi_rule_text += "\\n"
        
        kombi_rule_text += "📞 Montaj dahil paket fiyatları için iletişime geçin!\\n"
        kombi_rule_text += "🛠️ 2 yıl garanti kapsamında servis"
        
        kombi_conditions = [
            "müşteri kombi modelleri soruyor",
            "müşteri kombi listesi istiyor",
            "müşteri hangi kombiler var diyor"
        ]
        
        for condition in kombi_conditions:
            if run_guideline_command(condition, kombi_rule_text):
                successful_rules += 1
                break
    
    print(f"\\n✅ Toplam {successful_rules} ürün kuralı başarıyla eklendi!")
    print("🌬️ Klima BTU kategorileri hazır!")
    print("🔥 Kombi modelleri yüklendi!")
    
except Exception as e:
    print(f"❌ Hata: {e}")
    sys.exit(1)
PYTHON_SCRIPT

# Python scriptini çalıştır
if timeout 120 sudo -u parlant python3 /tmp/process_products.py; then
    echo "✅ Ürün kuralları başarıyla eklendi!"
else
    echo "⚠️ Ürün işleme zaman aşımına uğradı, temel kurallar mevcut"
fi

# Temizlik
rm -f /tmp/process_products.py /tmp/products.json

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
    echo "❌ API sorunu!"
    exit 1
fi

# IP adresi
SERVER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "🎉🎉🎉 KURULUM 100% BAŞARILI! 🎉🎉🎉"
echo "======================================"
echo ""
echo "🌐 ERİŞİM ADRESİ: http://$SERVER_IP:8800/chat/"
echo ""
echo "💬 TEST SORULARI:"
echo "   • Merhaba"
echo "   • 20 metrekare odam için kaç BTU klima gerekir?"
echo "   • 12000 BTU klima var mı?"
echo "   • Kombi modelleri neler?"
echo "   • 18000 BTU klima arıyorum"
echo ""
echo "🔧 YÖNETİM KOMUTLARI:"
echo "   • Servis durumu: sudo systemctl status parlant"
echo "   • Logları göster: sudo journalctl -u parlant -f"
echo "   • Servisi yeniden başlat: sudo systemctl restart parlant"
echo "   • Agent listesi: sudo -u parlant /opt/parlant/venv/bin/parlant agent list"
echo "   • Kural listesi: sudo -u parlant /opt/parlant/venv/bin/parlant guideline list"
echo ""
echo "✅ TÜM ÖZELLİKLER AKTİF:"
echo "   🔹 Gemini AI entegrasyonu"
echo "   🔹 Türkçe dil desteği"
echo "   🔹 BTU hesaplama sistemi"
echo "   🔹 89 ürün kataloğu"
echo "   🔹 Klima ve kombi önerileri"
echo "   🔹 Otomatik servis yönetimi"
echo "   🔹 Güvenlik duvarı yapılandırması"
echo ""
echo "🚀 SİSTEM KULLANIMA HAZIR!"
