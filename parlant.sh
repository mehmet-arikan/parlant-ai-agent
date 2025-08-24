#!/bin/bash
set -e

echo "🚀 Parlant JSON Q&A Sistemi Kuruluyor..."

# Önceki kurulumu temizle
sudo systemctl stop parlant 2>/dev/null || true
sudo systemctl disable parlant 2>/dev/null || true
sudo rm -rf /opt/parlant
sudo rm -f /etc/systemd/system/parlant.service
sudo systemctl daemon-reload

# Gerekli paketler
sudo apt update
sudo apt install -y python3 python3-pip python3-venv git curl jq

# Parlant dizini oluştur
sudo mkdir -p /opt/parlant
cd /opt/parlant

# Parlant kur
sudo git clone https://github.com/emcie-co/parlant.git .
sudo chown -R $USER:$USER /opt/parlant
python3 -m venv venv
source venv/bin/activate
venv/bin/pip install "parlant[gemini]"

# JSON dosyasını indir
echo "📊 JSON verisi indiriliyor..."
curl -s "https://dl.dropboxusercontent.com/scl/fi/6fyouegedqg9jl2fkap01/www.alarko-carrier.com.tr.output.20250731-202614.json?rlkey=h1k85rix5hsh1uawqa6loln3c&st=w55o63wv&dl=0" > web_data.json

# Özel Python handler oluştur
cat > custom_handler.py << 'EOF'
import json
import os
import google.generativeai as genai
from parlant.core.nlp.service import NLPService
from parlant.core.services.tools.service_registry import ServiceRegistry

class JSONQAHandler:
    def __init__(self):
        # JSON verisini yükle
        with open('/opt/parlant/web_data.json', 'r', encoding='utf-8') as f:
            self.json_data = json.load(f)
        
        # Gemini ayarları
        api_key = os.environ.get('GEMINI_API_KEY')
        if api_key:
            genai.configure(api_key=api_key)
            self.model = genai.GenerativeModel('gemini-1.5-flash')
    
    def extract_relevant_data(self, question):
        """Soruya göre JSON'dan ilgili veriyi çıkar"""
        results = self.json_data.get('results', [])
        
        # Temel istatistikler
        stats = {
            'total_requests': len(results),
            'successful': len([r for r in results if r.get('status') == 200]),
            'failed': len([r for r in results if r.get('status') != 200]),
            'avg_load_time': 0,
            'total_size_mb': 0
        }
        
        # Yükleme süreleri
        load_times = [r.get('elapsedTime', 0) for r in results if r.get('elapsedTime')]
        if load_times:
            stats['avg_load_time'] = sum(load_times) / len(load_times)
        
        # Dosya boyutları
        file_sizes = [r.get('size', 0) for r in results if r.get('size')]
        if file_sizes:
            stats['total_size_mb'] = sum(file_sizes) / 1024 / 1024
        
        # En yavaş dosyalar
        slow_files = sorted(
            [(r.get('elapsedTime', 0), r.get('url', '').split('/')[-1]) 
             for r in results if r.get('elapsedTime', 0) > 2], 
            reverse=True
        )[:5]
        
        # En büyük dosyalar
        large_files = sorted(
            [(r.get('size', 0) / 1024 / 1024, r.get('url', '').split('/')[-1]) 
             for r in results if r.get('size', 0) > 500000], 
            reverse=True
        )[:5]
        
        # Hatalı dosyalar
        error_files = [(r.get('status'), r.get('url', '').split('/')[-1]) 
                       for r in results if r.get('status') != 200][:10]
        
        return {
            'stats': stats,
            'slow_files': slow_files,
            'large_files': large_files,
            'error_files': error_files
        }
    
    def process_question(self, question):
        """Kullanıcı sorusunu işle"""
        try:
            # JSON'dan ilgili veriyi çıkar
            data = self.extract_relevant_data(question)
            
            # Gemini'ye gönderilecek prompt
            prompt = f"""
Sen bir web performans uzmanısın. Aşağıdaki veriler www.alarko-carrier.com.tr sitesinin performans analizi sonuçlarıdır.

PERFORMANS VERİLERİ:
- Toplam kaynak: {data['stats']['total_requests']}
- Başarılı istekler: {data['stats']['successful']}
- Başarısız istekler: {data['stats']['failed']}
- Ortalama yükleme süresi: {data['stats']['avg_load_time']:.2f} saniye
- Toplam veri boyutu: {data['stats']['total_size_mb']:.1f} MB

EN YAVAŞ DOSYALAR (>2 saniye):
{chr(10).join([f"- {time:.2f}s: {filename}" for time, filename in data['slow_files'][:3]])}

EN BÜYÜK DOSYALAR (>500KB):
{chr(10).join([f"- {size:.1f}MB: {filename}" for size, filename in data['large_files'][:3]])}

HATALAR:
{chr(10).join([f"- HTTP {status}: {filename}" for status, filename in data['error_files'][:5]])}

KULLANICI SORUSU: {question}

Bu verilere dayanarak soruyu Türkçe olarak cevapla. Emojiler kullan ve pratik önerilerde bulun.
"""
            
            # Gemini'ye sor
            response = self.model.generate_content(prompt)
            return response.text
            
        except Exception as e:
            return f"❌ Analiz hatası: {str(e)}"

# Global handler
qa_handler = JSONQAHandler()

def handle_user_message(message):
    """Kullanıcı mesajını işle"""
    return qa_handler.process_question(message)
EOF

# Gemini API anahtarı iste
echo ""
echo "🔑 Gemini API anahtarınızı girin:"
read -p "API Key: " api_key

# .env dosyası oluştur
cat > .env << EOF
GEMINI_API_KEY=$api_key
EOF

# Systemd servisi
sudo tee /etc/systemd/system/parlant.service > /dev/null << EOF
[Unit]
Description=Parlant JSON Q&A System
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/parlant
Environment=PATH=/opt/parlant/venv/bin
EnvironmentFile=/opt/parlant/.env
ExecStart=/opt/parlant/venv/bin/parlant-server run --gemini
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Agent oluştur
sudo systemctl daemon-reload
sudo systemctl enable parlant
sudo systemctl start parlant

# Biraz bekle sonra agent oluştur
sleep 10

# Agent oluştur (minimal)
/opt/parlant/venv/bin/parlant agent create \
    --name "Web Performans Uzmanı" \
    --description "Alarko Carrier web sitesi performans verilerini analiz eder ve sorulara cevap verir."

# Tek kural ekle - JSON handler kullan
/opt/parlant/venv/bin/parlant guideline create \
    --condition "kullanıcı herhangi bir soru soruyor" \
    --action "import sys; sys.path.append('/opt/parlant'); from custom_handler import handle_user_message; return handle_user_message(user_message)"

# UFW ayarları
sudo ufw allow 8800 2>/dev/null || true

echo ""
echo "✅ KURULUM TAMAMLANDI!"
echo "🌐 Web arayüzü: http://$(hostname -I | awk '{print $1}'):8800"
echo ""
echo "📝 Sistem hazır! Artık herhangi bir performans sorusu sorabilirsiniz:"
echo "• Web sitesi performansı nasıl?"
echo "• En yavaş yüklenen dosyalar neler?"
echo "• Hangi dosyalar en büyük?"
echo "• Hata alan dosyalar var mı?"
echo ""
echo "🤖 Sistem kullanıcının her sorusunu JSON verileriyle birlikte Gemini'ye gönderiyor!"
