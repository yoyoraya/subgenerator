#!/bin/bash

# تنظیمات پیش‌فرض
BOT_DIR="/home/$USER/ftpsub"
SERVICE_FILE="/etc/systemd/system/ftpsub.service"
CONFIG_FILE="$BOT_DIR/config.py"
BOT_FILE="$BOT_DIR/ftpsub.py"

# تابع برای نصب ربات
install_bot() {
    echo "Please enter your Telegram Bot Token:"
    read TELEGRAM_TOKEN

    echo "Please enter your FTP host (without https://):"
    read FTP_HOST

    echo "Please enter your FTP port (default: 21):"
    read FTP_PORT
    FTP_PORT=${FTP_PORT:-21}

    echo "Please enter your FTP username:"
    read FTP_USER

    echo "Please enter your FTP password:"
    read -s FTP_PASS

    echo "Please enter your FTP directory (e.g., /public_html/):"
    read FTP_DIR

    # نصب پیش‌نیازها
    echo "Installing prerequisites..."
    sudo apt-get update
    sudo apt-get install -y python3 python3-pip
    pip3 install python-telegram-bot

    # ایجاد دایرکتوری ربات
    mkdir -p $BOT_DIR
    cd $BOT_DIR

    # ایجاد فایل پیکربندی
    cat > $CONFIG_FILE <<EOL
TELEGRAM_TOKEN = "$TELEGRAM_TOKEN"
FTP_HOST = "$FTP_HOST"
FTP_PORT = $FTP_PORT
FTP_USER = "$FTP_USER"
FTP_PASS = "$FTP_PASS"
FTP_DIR = "$FTP_DIR"
EOL

    # ایجاد فایل ربات
    cat > $BOT_FILE <<EOL
import os
import logging
from telegram import Update, ReplyKeyboardMarkup, InlineKeyboardMarkup, InlineKeyboardButton
from telegram.constants import ChatAction
from telegram.ext import (
    Application,
    CommandHandler,
    MessageHandler,
    filters,
    ConversationHandler,
    CallbackContext,
    PersistenceInput,
)
from ftplib import FTP, error_perm
from config import TELEGRAM_TOKEN, FTP_HOST, FTP_PORT, FTP_USER, FTP_PASS, FTP_DIR

# تنظیمات لاگ
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)

# مراحل گفتگو
REMARK, LINKS = range(2)

# شروع ربات
async def start(update: Update, context: CallbackContext) -> int:
    await update.message.reply_text(
        "Hello! To generate a subscription link, click the 'Generate' button.",
        reply_markup=ReplyKeyboardMarkup([['Generate']], one_time_keyboard=True)
    )
    return REMARK

# دریافت remark
async def get_remark(update: Update, context: CallbackContext) -> int:
    await update.message.reply_text("Please enter the remark:")
    return LINKS

# دریافت لینک‌ها
async def get_links(update: Update, context: CallbackContext) -> int:
    remark = update.message.text
    context.user_data['remark'] = remark
    await update.message.reply_text("Please send the subscription links, one per line:")
    return ConversationHandler.END

# پردازش لینک‌ها و ایجاد فایل PHP
async def process_links(update: Update, context: CallbackContext) -> None:
    await update.message.reply_chat_action(ChatAction.TYPING)
    
    links = update.message.text.split('\n')
    remark = context.user_data.get('remark', 'default_remark')
    
    php_content = ''
    for link in links:
        php_content += (
            '<div style="user-select: none; color: transparent;">\n'
            '<?php\n'
            f'$url = "{link.strip()}";\n'
            '$content = file_get_contents($url);\n'
            'echo $content;\n'
            '?>\n'
            '</div>\n\n'
        )
    
    filename = f"{remark}.php"
    try:
        with open(filename, 'w') as f:
            f.write(php_content)
        logger.info(f"File {filename} created successfully.")
    except Exception as e:
        logger.error(f"Error creating file: {e}")
        await update.message.reply_text("An error occurred while creating the file. Please try again.")
        return
    
    await update.message.reply_chat_action(ChatAction.UPLOAD_DOCUMENT)
    
    try:
        ftp = FTP()
        ftp.connect(FTP_HOST, FTP_PORT)
        logger.info("FTP connection successful.")
        
        ftp.login(FTP_USER, FTP_PASS)
        logger.info("FTP login successful.")
        
        ftp.cwd(FTP_DIR)
        logger.info(f"Changed to directory {FTP_DIR}.")
        
        with open(filename, 'rb') as f:
            ftp.storbinary(f'STOR {filename}', f)
        logger.info(f"File {filename} uploaded successfully.")
        
        ftp.quit()
        logger.info("FTP connection closed.")
        
        link = f"https://{FTP_HOST}/{remark}"
        keyboard = InlineKeyboardMarkup([
            [InlineKeyboardButton(text="🛡️ Copy Subscription Link", url=link)]
        ])
        
        await update.message.reply_text(
            f"Your subscription link is ready. Click the button below to copy it:\n\n🛡️ {remark}",
            reply_markup=keyboard
        )
    
    except error_perm as e:
        logger.error(f"FTP access error: {e}")
        await update.message.reply_text("An error occurred while accessing the FTP server. Please try again.")
    except Exception as e:
        logger.error(f"File upload error: {e}")
        await update.message.reply_text("An error occurred while uploading the file. Please try again.")
    finally:
        if os.path.exists(filename):
            os.remove(filename)
            logger.info(f"Temporary file {filename} deleted.")

def main() -> None:
    persistence = PersistenceInput(filename="bot_persistence")
    application = Application.builder().token(TELEGRAM_TOKEN).persistence(persistence).build()
    
    conv_handler = ConversationHandler(
        entry_points=[CommandHandler('start', start)],
        states={
            REMARK: [MessageHandler(filters.TEXT & ~filters.COMMAND, get_remark)],
            LINKS: [MessageHandler(filters.TEXT & ~filters.COMMAND, get_links)],
        },
        fallbacks=[],
        persistent=True,
    )
    
    application.add_handler(conv_handler)
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, process_links))
    
    application.run_polling()

if __name__ == '__main__':
    main()
EOL

    # ایجاد سرویس سیستم
    sudo bash -c "cat > $SERVICE_FILE <<EOL
[Unit]
Description=FTPSUB Bot
After=network.target

[Service]
User=$USER
WorkingDirectory=$BOT_DIR
ExecStart=/usr/bin/python3 $BOT_DIR/ftpsub.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL"

    # بارگذاری و فعال‌سازی سرویس
    sudo systemctl daemon-reload
    sudo systemctl enable ftpsub.service
    sudo systemctl start ftpsub.service

    echo "Bot installed and started successfully!"
}

# تابع برای تغییر توکن ربات
change_bot_token() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Bot is not installed. Please install the bot first."
        return
    fi

    echo "Please enter your new Telegram Bot Token:"
    read TELEGRAM_TOKEN

    # به‌روزرسانی توکن در فایل پیکربندی
    sed -i "s/TELEGRAM_TOKEN = .*/TELEGRAM_TOKEN = \"$TELEGRAM_TOKEN\"/" $CONFIG_FILE

    # راه‌اندازی مجدد سرویس
    sudo systemctl restart ftpsub.service

    echo "Bot token updated successfully!"
}

# تابع برای تغییر تنظیمات FTP
change_ftp_details() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Bot is not installed. Please install the bot first."
        return
    fi

    echo "Please enter your new FTP host (without https://):"
    read FTP_HOST

    echo "Please enter your new FTP port (default: 21):"
    read FTP_PORT
    FTP_PORT=${FTP_PORT:-21}

    echo "Please enter your new FTP username:"
    read FTP_USER

    echo "Please enter your new FTP password:"
    read -s FTP_PASS

    echo "Please enter your new FTP directory (e.g., /public_html/):"
    read FTP_DIR

    # به‌روزرسانی تنظیمات FTP در فایل پیکربندی
    sed -i "s/FTP_HOST = .*/FTP_HOST = \"$FTP_HOST\"/" $CONFIG_FILE
    sed -i "s/FTP_PORT = .*/FTP_PORT = $FTP_PORT/" $CONFIG_FILE
    sed -i "s/FTP_USER = .*/FTP_USER = \"$FTP_USER\"/" $CONFIG_FILE
    sed -i "s/FTP_PASS = .*/FTP_PASS = \"$FTP_PASS\"/" $CONFIG_FILE
    sed -i "s/FTP_DIR = .*/FTP_DIR = \"$FTP_DIR\"/" $CONFIG_FILE

    # راه‌اندازی مجدد سرویس
    sudo systemctl restart ftpsub.service

    echo "FTP details updated successfully!"
}

# تابع برای پاک کردن ربات
uninstall_bot() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Bot is not installed. Nothing to uninstall."
        return
    fi

    # توقف و غیرفعال‌سازی سرویس
    sudo systemctl stop ftpsub.service
    sudo systemctl disable ftpsub.service
    sudo rm -f $SERVICE_FILE
    sudo systemctl daemon-reload

    # حذف دایرکتوری ربات
    rm -rf $BOT_DIR

    echo "Bot uninstalled successfully!"
}

# منوی اصلی
while true; do
    echo "Please select an option:"
    echo "0 - Install"
    echo "1 - Change Bot Token"
    echo "2 - Change FTP Details"
    echo "3 - Uninstall"
    echo "4 - Exit"
    read -p "Enter your choice: " choice

    case $choice in
        0)
            install_bot
            ;;
        1)
            change_bot_token
            ;;
        2)
            change_ftp_details
            ;;
        3)
            uninstall_bot
            ;;
        4)
            echo "Exiting..."
            break
            ;;
        *)
            echo "Invalid choice. Please try again."
            ;;
    esac
done
