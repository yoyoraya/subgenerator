#!/bin/bash

test_ftp_connection() {
    echo "🔌 Testing FTP connection to $1:$2..."
    python3 - <<EOF
import sys
from ftplib import FTP

try:
    ftp = FTP()
    ftp.connect("$1", $2)
    ftp.login("$3", "$4")
    ftp.cwd("$5")
    print("✅ FTP connection successful!")
    ftp.quit()
    sys.exit(0)
except Exception as e:
    print(f"❌ FTP Error: {str(e)}")
    sys.exit(1)
EOF
}

while true; do
    clear
    echo "📲 Telegram Bot Setup"
    
    read -p "Bot Token: " BOT_TOKEN
    read -p "FTP Host (e.g., ftp.example.com): " FTP_HOST
    read -p "FTP Port (default 21): " FTP_PORT
    FTP_PORT=${FTP_PORT:-21}
    read -p "FTP Username: " FTP_USER
    read -p "FTP Password: " FTP_PASS
    read -p "FTP Upload Directory (e.g., /public_html): " FTP_DIR
    FTP_DIR=${FTP_DIR%/}

    if test_ftp_connection "$FTP_HOST" "$FTP_PORT" "$FTP_USER" "$FTP_PASS" "$FTP_DIR"; then
        echo "Creating .env file..."
        cat > .env <<EOL
BOT_TOKEN=$BOT_TOKEN
FTP_HOST=$FTP_HOST
FTP_PORT=$FTP_PORT
FTP_USER=$FTP_USER
FTP_PASS=$FTP_PASS
FTP_DIR=$FTP_DIR
EOL
        break
    else
        echo
        read -p "Invalid credentials! Press Enter to retry..."
    fi
done
cat > ftpv2ray.py <<EOF
#bot file code
import os
from dotenv import load_dotenv
from ftplib import FTP
from telegram import Update, ReplyKeyboardMarkup
from telegram.ext import (
    ApplicationBuilder,
    CommandHandler,
    MessageHandler,
    filters,
    ConversationHandler,
    ContextTypes
)

load_dotenv()
TOKEN = os.getenv('BOT_TOKEN')
FTP_HOST = os.getenv('FTP_HOST')
FTP_PORT = int(os.getenv('FTP_PORT'))
FTP_USER = os.getenv('FTP_USER')
FTP_PASS = os.getenv('FTP_PASS')
FTP_DIR = os.getenv('FTP_DIR')

# حالت‌های مکالمه
LINKS, FILENAME = range(2)

# ایجاد کیبورد با دکمه استارت
START_KEYBOARD = ReplyKeyboardMarkup([['/start']], resize_keyboard=True)

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """شروع مکالمه و ریست داده‌های کاربر"""
    context.user_data.clear()
    await update.message.reply_text(
        'لطفاً لینک‌های V2ray را ارسال کنید (هر خط یک لینک)\n'
        '⚠️ فقط http/https و آدرس IP مجاز است!',
        reply_markup=START_KEYBOARD
    )
    return LINKS

async def process_links(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """پردازش لینک‌های ارسالی"""
    # اگر کاربر /start فرستاد، مکالمه را ریست کنید
    if update.message.text == '/start':
        return await start(update, context)
    
    links = [link.strip() for link in update.message.text.split('\n') if link.strip()]
    valid_links = []
    invalid_links = []
    
    for link in links:
        # اعتبارسنجی پیشرفته (فقط http/https و IP)
        is_valid = (
            link.startswith(('http://', 'https://')) or
            (link.replace('.', '').isdigit() and '/' in link)  # آدرس IP با مسیر
        )
        
        if is_valid:
            valid_links.append(link)
        else:
            invalid_links.append(link)
    
    # ارسال پیام برای لینک‌های نامعتبر
    if invalid_links:
        error_msg = "❌ لینک‌های نامعتبر:\n" + "\n".join(invalid_links)
        await update.message.reply_text(error_msg)
    
    if not valid_links:
        await update.message.reply_text("⚠️ هیچ لینک معتبری یافت نشد! دوباره ارسال کنید.")
        return LINKS
    
    context.user_data['links'] = valid_links
    await update.message.reply_text('✅ لینک‌های معتبر دریافت شد! نام فایل را وارد کنید:')
    return FILENAME

def generate_php(filename, links):
    """ساخت فایل PHP"""
    php_code = ""
    for link in links:
        php_code += f'''<div style="user-select: none; color: transparent;">
<?php
$url = "{link}";
$content = file_get_contents($url);
echo $content;
?>
</div>\n\n'''
    php_code = php_code.rsplit('\n\n', 1)[0]
    
    with open(f'{filename}.php', 'w', encoding='utf-8') as f:
        f.write(php_code)

def upload_to_ftp(filename):
    local_file = f'{filename}.php'  # تعریف متغیر خارج از بلوک try
    
    try:
        # اتصال به FTP و آپلود
        with FTP() as ftp:
            ftp.connect(FTP_HOST, FTP_PORT)
            ftp.login(FTP_USER, FTP_PASS)
            ftp.cwd(FTP_DIR)
            
            # آپلود فایل
            with open(local_file, 'rb') as f:
                ftp.storbinary(f'STOR {filename}.php', f)
        
        # حذف فایل محلی پس از موفقیت
        if os.path.exists(local_file):
            os.remove(local_file)
        
        # ساخت لینک
        base_url = f"https://{FTP_HOST.replace('ftp.', '')}"
        clean_path = FTP_DIR.replace('/public_html', '')
        return f"{base_url}{clean_path}/{filename}"
    
    except Exception as e:
        # حذف فایل محلی در صورت خطا
        if os.path.exists(local_file):
            os.remove(local_file)
        raise Exception(f"خطا در آپلود: {str(e)}")

async def process_filename(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """پردازش نام فایل"""
    # اگر کاربر /start فرستاد، مکالمه را ریست کنید
    if update.message.text == '/start':
        return await start(update, context)
    
    filename = update.message.text.strip()
    if not filename:
        await update.message.reply_text("⚠️ نام فایل نمی‌تواند خالی باشد!")
        return FILENAME
    
    try:
        links = context.user_data['links']
        generate_php(filename, links)
        file_url = upload_to_ftp(filename)
        await update.message.reply_text(f'✅ فایل آماده است!\nلینک دانلود:\n{file_url}')
    except Exception as e:
        await update.message.reply_text(f'❌ خطا: {str(e)}')
    
    return ConversationHandler.END

def main():
    application = ApplicationBuilder().token(TOKEN).build()

    conv_handler = ConversationHandler(
        entry_points=[CommandHandler('start', start)],
        states={
            LINKS: [MessageHandler(filters.TEXT & ~filters.COMMAND, process_links)],
            FILENAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, process_filename)]
        },
        fallbacks=[CommandHandler('start', start)]  # ریست با /start در هر مرحله
    )

    application.add_handler(conv_handler)
    application.run_polling()

if __name__ == '__main__':
    main()

#end of bot file   
EOF
echo "📦 Installing dependencies..."
pip3 install python-telegram-bot python-dotenv

echo "🔒 Setting permissions..."
chmod 600 .env
chmod +x ftpv2ray.py

echo -e "\n🎉 Setup complete! Start the bot:"
echo "python3 ftpv2ray.py"
# Create systemd Service
echo "🛠 Creating systemd service..."
cat > /etc/systemd/system/v2ray-bot.service <<EOL
[Unit]
Description=V2ray Telegram Bot
After=network.target

[Service]
User=root
WorkingDirectory=$(pwd)
ExecStart=/usr/bin/python3 $(pwd)/ftpv2ray.py
Restart=always

[Install]
WantedBy=multi-user.target
EOL
# Running Service
systemctl daemon-reload
systemctl enable v2ray-bot
systemctl start v2ray-bot
echo -e "\n🎉 Setup complete! Bot is running automatically."
