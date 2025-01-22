#!/bin/bash

# Configuration
SERVICE_NAME="v2ray-bot"
PROJECT_DIR=$(pwd)
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

check_status() {
    echo "🔍 Checking system status..."
    
    # Check service status
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo "✅ Service Status: Running"
    else
        echo "❌ Service Status: Not running"
    fi
    
    # Check service enabled
    if systemctl is-enabled --quiet $SERVICE_NAME; then
        echo "✅ Service Auto-start: Enabled"
    else
        echo "❌ Service Auto-start: Disabled"
    fi
    
    # Check files existence
    echo -e "\n📂 Files Status:"
    [ -f ".env" ] && echo "✅ .env file exists" || echo "❌ .env file missing"
    [ -f "ftpv2ray.py" ] && echo "✅ ftpv2ray.py exists" || echo "❌ ftpv2ray.py missing"
    [ -f "$SERVICE_FILE" ] && echo "✅ Service file exists" || echo "❌ Service file missing"
}

show_menu() {
    echo -e "\n📋 Main Menu:"
    echo "1) Install/Reinstall Bot"
    echo "2) Remove Bot Completely"
    echo "3) Exit"
    read -p "Select option [1-3]: " menu_choice
}

install_bot() {
    echo "🚀 Starting installation process..."
    
    # Remove existing files
    [ -f ".env" ] && rm -f .env
    [ -f "ftpv2ray.py" ] && rm -f ftpv2ray.py
    
    # Setup process
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
    # Create bot file
cat > ftpv2ray.py <<EOF
#bot file code
# -*- coding: utf-8 -*-
import os
from difflib import SequenceMatcher
from ftplib import FTP
from dotenv import load_dotenv
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
LINKS, FILENAME, SEARCH = range(3)

# کیبورد اصلی
START_KEYBOARD = ReplyKeyboardMarkup(
    [['/start', '/search', '/generate']],
    resize_keyboard=True
)

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """شروع مکالمه جدید"""
    context.user_data.clear()
    await update.message.reply_text(
        '📡 لینک‌های V2ray را ارسال کنید (هر خط یک لینک)\n'
        '⚠️ فقط http/https و آدرس IP مجاز است!',
        reply_markup=START_KEYBOARD
    )
    return LINKS

async def search(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """شروع جستجو"""
    context.user_data.clear()
    await update.message.reply_text('🔍 نام کانفیگ را وارد کنید:')
    return SEARCH

async def generate(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """شروع تولید فایل جدید"""
    context.user_data.clear()
    await update.message.reply_text(
        '📡 لینک‌های V2ray را ارسال کنید (هر خط یک لینک)\n'
        '⚠️ فقط http/https و آدرس IP مجاز است!',
        reply_markup=START_KEYBOARD
    )
    return LINKS

def search_ftp_files(query):
    """جستجو در فایل‌های FTP"""
    similar_files = []
    try:
        with FTP() as ftp:
            ftp.connect(FTP_HOST, FTP_PORT)
            ftp.login(FTP_USER, FTP_PASS)
            ftp.cwd(FTP_DIR)
            files = ftp.nlst()
            php_files = [f for f in files if f.endswith('.php')]
            
            for file in php_files:
                similarity = SequenceMatcher(None, query, file).ratio()
                if similarity >= 0.4:
                    similar_files.append(file)
    except Exception as e:
        raise Exception(f"خطا: {str(e)}")
    return similar_files

async def process_search(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """پردازش جستجو"""
    query = update.message.text.strip()
    try:
        similar_files = search_ftp_files(query)
        if not similar_files:
            await update.message.reply_text('❌ نتیجه‌ای یافت نشد!')
            return ConversationHandler.END
        
        results = []
        base_url = f"https://{FTP_HOST.replace('ftp.', '')}"
        clean_path = FTP_DIR.replace('/public_html', '')
        
        for file in similar_files:
            file_name = file.replace('.php', '')
            results.append(f"🔗 {file_name}\n{base_url}{clean_path}/{file_name}")
        
        await update.message.reply_text(
            f'🔍 نتایج برای "{query}":\n\n' + '\n\n'.join(results)
        )
    except Exception as e:
        await update.message.reply_text(f'❌ خطا: {str(e)}')
    return ConversationHandler.END

async def process_links(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """پردازش لینک‌های دریافتی"""
    links = [link.strip() for link in update.message.text.split('\n')]
    valid_links = []
    invalid_links = []
    
    for link in links:
        if link.startswith(('http://', 'https://')) or (link.replace('.', '').isdigit() and '/' in link):
            valid_links.append(link)
        else:
            invalid_links.append(link)
    
    if invalid_links:
        await update.message.reply_text("❌ لینک‌های نامعتبر:\n" + "\n".join(invalid_links))
    
    if not valid_links:
        await update.message.reply_text("⚠️ لینک معتبری یافت نشد!")
        return LINKS
    
    context.user_data['links'] = valid_links
    await update.message.reply_text('✅ لینک‌ها ذخیره شدند. نام فایل را وارد کنید:')
    return FILENAME

def generate_php(filename, links):
    """تولید محتوای PHP با سینتکس صحیح"""
    php_code = ""
    for link in links:
        php_code += f'''<div style="user-select: none; color: transparent;">
<?php
$url = "{link}";
$content = file_get_contents($url);
echo $content;
?>
</div>\n\n'''
    php_code = php_code.rstrip('\n\n')  # حذف خطوط خالی اضافی در انتها
    with open(f'{filename}.php', 'w', encoding='utf-8') as f:
        f.write(php_code)

def upload_to_ftp(filename):
    """آپلود فایل به FTP"""
    local_file = f'{filename}.php'
    try:
        with FTP() as ftp:
            ftp.connect(FTP_HOST, FTP_PORT)
            ftp.login(FTP_USER, FTP_PASS)
            ftp.cwd(FTP_DIR)
            with open(local_file, 'rb') as f:
                ftp.storbinary(f'STOR {filename}.php', f)
        if os.path.exists(local_file):
            os.remove(local_file)
        base_url = f"https://{FTP_HOST.replace('ftp.', '')}"
        clean_path = FTP_DIR.replace('/public_html', '')
        return f"{base_url}{clean_path}/{filename}"
    except Exception as e:
        if os.path.exists(local_file):
            os.remove(local_file)
        raise Exception(f"خطا: {str(e)}")

async def process_filename(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """پردازش نام فایل"""
    filename = update.message.text.strip()
    if not filename:
        await update.message.reply_text("⚠️ نام فایل نمی‌تواند خالی باشد!")
        return FILENAME
    
    try:
        links = context.user_data['links']
        generate_php(filename, links)
        file_url = upload_to_ftp(filename)
        await update.message.reply_text(f'✅ فایل آماده است!\nلینک: {file_url}')
    except Exception as e:
        await update.message.reply_text(f'❌ خطا: {str(e)}')
    return ConversationHandler.END

def main():
    application = ApplicationBuilder().token(TOKEN).build()
    
    # دستوراتی که می‌توانند فرایند فعلی را لغو کنند
    cancel_handlers = [
        CommandHandler('start', start),
        CommandHandler('search', search),
        CommandHandler('generate', generate)
    ]

    conv_handler = ConversationHandler(
        entry_points=[
            CommandHandler('start', start),
            CommandHandler('search', search),
            CommandHandler('generate', generate)
        ],
        states={
            LINKS: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, process_links),
                *cancel_handlers
            ],
            FILENAME: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, process_filename),
                *cancel_handlers
            ],
            SEARCH: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, process_search),
                *cancel_handlers
            ]
        },
        fallbacks=cancel_handlers
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
    
    echo "🛠 Creating systemd service..."
    cat > $SERVICE_FILE <<EOL
[Unit]
Description=V2ray Telegram Bot
After=network.target
[Service]
User=root
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/python3 $PROJECT_DIR/ftpv2ray.py
Restart=always
[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl start $SERVICE_NAME
    
    echo -e "\n🎉 Installation complete! Bot is running automatically."
}

remove_bot() {
    echo "⚠️ WARNING: This will completely remove the bot!"
    read -p "Are you sure? [y/N] " confirm
    if [[ $confirm =~ [yY] ]]; then
        echo "🗑 Starting removal process..."
        
        # Stop and disable service
        systemctl stop $SERVICE_NAME 2>/dev/null
        systemctl disable $SERVICE_NAME 2>/dev/null
        rm -f $SERVICE_FILE
        
        # Remove project files
        rm -f .env ftpv2ray.py
        
        # Reload systemd
        systemctl daemon-reload
        systemctl reset-failed
        
        echo "✅ All bot components removed successfully!"
    else
        echo "❌ Removal canceled."
    fi
}

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

# Main loop
while true; do
    clear
    check_status
    show_menu
    
    case $menu_choice in
        1)
            install_bot
            ;;
        2)
            remove_bot
            ;;
        3)
            echo "👋 Exiting..."
            exit 0
            ;;
        *)
            echo "❌ Invalid option!"
            ;;
    esac
    
    read -p "Press Enter to continue..."
done
