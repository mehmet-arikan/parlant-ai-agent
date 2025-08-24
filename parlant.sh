#!/bin/bash
set -e

echo "🚀 Parlant JSON Q&A Sistemi Kuruluyor..."

# Önceki kurulumu temizle
echo "🧹 Önceki kurulum temizleniyor..."
sudo systemctl stop parlant 2>/dev/null || true
sudo systemctl disable parlant 2>/dev/null || true
sudo rm -rf /opt/parlant
sudo rm -f /etc/systemd/system/parlant.service
sudo systemctl daemon-reload

# API key iste
get_api_key

# Gerekli paketler
echo "📦 Paketler kuruluyor..."
sudo apt update
sudo apt install -y python3 python3-pip python3-venv git curl jq

# Parlant dizini oluştur
sudo mkdir -p /opt/parlant
cd /opt/parlant

# Parlant kur
echo "⚙️ Parlant kuruluyor..."
sudo git clone https://github.com/emcie-co/parlant.git .
sudo chown -R $USER:$USER /opt/parlant
python3 -m venv venv
source venv/bin/activate
venv/bin/pip install "parlant[gemini]"

# JSON dosyasını indir
echo "📊 JSON verisi indiriliyor..."
curl -s "https://dl.dropboxusercontent.com/scl/fi/6fyouegedqg9jl2fkap01/www.alarko-carrier.com.tr.output.20250731-202614.json?rlkey=h1k85rix5hsh1uawqa6loln3c&st=w55o63wv&dl=0" > web_data.json

# Python handler oluştur
cat > custom_handler.py << 'EOF'
import json
import os
import google.generativeai as genai

class JSONQAHandler:
    def __init__(self):
        with open('/opt/parlant/web_data.json', 'r', encoding='utf-8') as f:
            self.json_data = json.load(f)
        
        api_key = os.environ.get('GEMINI_API_KEY')
        if api_key:
            genai.configure(api_key=api_key)
            self.model = genai.GenerativeModel('gemini-1.5-flash')
    
    def extract_relevant_data(self, question):
        results = self.json_data.get('results', [])
        
        stats = {
            'total_requests': len(results),
            'successful': len([r for r in results if r.get('status') == 200]),
            'failed': len([r for r in results if r.get('status') != 200]),
            'avg_load_time': 0,
            'total_size_mb': 0
        }
        
        load_times = [r.get('elapsedTime', 0) for r in results if r.get('elapsedTime')]
        if load_times:
            stats['avg_load_time'] = sum(load_times) / len(load_times)
        
        file_sizes = [r.get('size', 0) for r in results if r.get('size')]
        if file_sizes:
            stats['total_size_mb'] = sum(file_sizes) / 1024 / 1024
        
        slow_files = sorted(
            [(r.get('elapsedTime', 0), r.get('url', '').split('/')[-1]) 
             for r in results if r.get('elapsedTime', 0) > 2], 
            reverse=True
        )[:5]
        
        large_files = sorted(
            [(r.get('size', 0) / 1024 / 1024, r.get('url', '').split('/')[-1]) 
             for r in results if r.get('size', 0) > 500000], 
            reverse=True
        )[:5]
        
        error_files = [(r.get('status'), r.get('url', '').split('/')[-1]) 
                       for r in results if r.get('status') != 200][:10]
        
        return {
            'stats': stats,
            'slow_files': slow_files,
            'large_files': large_files,
            'error_files': error_files
        }
    
    def process_question(self, question):
        try:
            data = self.extract_relevant_data(question)
            
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
            
            response = self.model.generate_content(prompt)
            return response.text
            
        except Exception as e:
            return f"❌ Analiz hatası: {str(e)}"

qa_handler = JSONQAHandler()

def handle_user_message(message):
    return qa_handler.process_question(message)
EOF

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
ExecStart=/opt/parlant/venv/bin/parlant-server run --gemini --host 0.0.0.0 --port 8080
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Servisi başlat
sudo systemctl daemon-reload
sudo systemctl enable parlant
sudo systemctl start parlant

# Biraz bekle
sleep 15

# Agent oluştur
/opt/parlant/venv/bin/parlant agent create \
    --name "Web Performans Uzmanı" \
    --description "Alarko Carrier web sitesi performans verilerini analiz eder ve sorulara cevap verir."

# Firewall
sudo ufw allow 8080 2>/dev/null || true

# Sonuç
local_ip=$(hostname -I | awk '{print $1}')
echo ""
echo "✅ KURULUM TAMAMLANDI!"
echo "🌐 Web arayüzü: http://$local_ip:8080"
echo ""
echo "📝 Test soruları:"
echo "• Web sitesi performansı nasıl?"
echo "• En yavaş dosyalar neler?"
echo "• Hangi dosyalar en büyük?"
