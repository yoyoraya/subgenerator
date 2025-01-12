#!/bin/bash

# تنظیمات پیش‌فرض
BOT_DIR="/root/ftpsub"  # تغییر مسیر به /root/ftpsub
SERVICE_FILE="/etc/systemd/system/ftpsub.service"
CONFIG_FILE="$BOT_DIR/config.py"
BOT_FILE="$BOT_DIR/ftpsub.py"

# تابع برای نمایش خطا و خروج
error_exit() {
    echo -e "${RED}Error: $1${NC}"
    exit 1
}

# تابع برای نمایش منو
show_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}          FTP Sub V2Ray Bot Menu        ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}0 - Install${NC}"
    echo -e "${GREEN}1 - Change Bot Token${NC}"
    echo -e "${GREEN}2 - Change FTP Details${NC}"
    echo -e "${GREEN}3 - Uninstall${NC}"
    echo -e "${RED}4 - Exit${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# تابع برای نصب ربات
install_bot() {
    echo -e "${YELLOW}Please enter your Telegram Bot Token:${NC}"
    read TELEGRAM_TOKEN

    echo -e "${YELLOW}Please enter your FTP host (without https://):${NC}"
    read FTP_HOST

    echo -e "${YELLOW}Please enter your FTP port (default: 21):${NC}"
    read FTP_PORT
    FTP_PORT=${FTP_PORT:-21}

    echo -e "${YELLOW}Please enter your FTP username:${NC}"
    read FTP_USER

    echo -e "${YELLOW}Please enter your FTP password:${NC}"
    read -s FTP_PASS

    echo -e "${YELLOW}Please enter your FTP directory (e.g., /public_html/):${NC}"
    read FTP_DIR

    # نصب پیش‌نیازها
    echo -e "${BLUE}Installing prerequisites...${NC}"
    sudo apt-get update || error_exit "Failed to update packages."
    sudo apt-get install -y python3 python3-pip || error_exit "Failed to install Python or pip."
    pip3 install python-telegram-bot || error_exit "Failed to install python-telegram-bot."

    # ایجاد دایرکتوری ربات
    sudo mkdir -p $BOT_DIR || error_exit "Failed to create bot directory."
    cd $BOT_DIR || error_exit "Failed to change to bot directory."

    # ایجاد فایل پیکربندی
    sudo bash -c "cat > $CONFIG_FILE <<EOL
TELEGRAM_TOKEN = \"$TELEGRAM_TOKEN\"
FTP_HOST = \"$FTP_HOST\"
FTP_PORT = $FTP_PORT
FTP_USER = \"$FTP_USER\"
FTP_PASS = \"$FTP_PASS\"
FTP_DIR = \"$FTP_DIR\"
EOL"
    [ $? -eq 0 ] || error_exit "Failed to create config file."

    # ایجاد فایل ربات
    sudo bash -c "cat > $BOT_FILE <<EOL
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
            f'$url = \"{link.strip()}\";\n'
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
EOL"
    [ $? -eq 0 ] || error_exit "Failed to create bot file."

    # ایجاد سرویس سیستم
    sudo bash -c "cat > $SERVICE_FILE <<EOL
[Unit]
Description=FTPSUB Bot
After=network.target

[Service]
User=root
WorkingDirectory=$BOT_DIR
ExecStart=/usr/bin/python3 $BOT_DIR/ftpsub.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL"
    [ $? -eq 0 ] || error_exit "Failed to create service file."

    # بارگذاری و فعال‌سازی سرویس
    sudo systemctl daemon-reload || error_exit "Failed to reload systemd daemon."
    sudo systemctl enable ftpsub.service || error_exit "Failed to enable service."
    sudo systemctl start ftpsub.service || error_exit "Failed to start service."

    echo -e "${GREEN}Bot installed and started successfully!${NC}"
}

# تابع برای تغییر توکن ربات
change_bot_token() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Bot is not installed. Please install the bot first.${NC}"
        return
    fi

    echo -e "${YELLOW}Please enter your new Telegram Bot Token:${NC}"
    read TELEGRAM_TOKEN

    # به‌روزرسانی توکن در فایل پیکربندی
    sudo sed -i "s/TELEGRAM_TOKEN = .*/TELEGRAM_TOKEN = \"$TELEGRAM_TOKEN\"/" $CONFIG_FILE

    # راه‌اندازی مجدد سرویس
    sudo systemctl restart ftpsub.service

    echo -e "${GREEN}Bot token updated successfully!${NC}"
}

# تابع برای تغییر تنظیمات FTP
change_ftp_details() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Bot is not installed. Please install the bot first.${NC}"
        return
    fi

    echo -e "${YELLOW}Please enter your new FTP host (without https://):${NC}"
    read FTP_HOST

    echo -e "${YELLOW}Please enter your new FTP port (default: 21):${NC}"
    read FTP_PORT
    FTP_PORT=${FTP_PORT:-21}

    echo -e "${YELLOW}Please enter your new FTP username:${NC}"
    read FTP_USER

    echo -e "${YELLOW}Please enter your new FTP password:${NC}"
    read -s FTP_PASS

    echo -e "${YELLOW}Please enter your new FTP directory (e.g., /public_html/):${NC}"
    read FTP_DIR

    # به‌روزرسانی تنظیمات FTP در فایل پیکربندی
    sudo sed -i "s/FTP_HOST = .*/FTP_HOST = \"$FTP_HOST\"/" $CONFIG_FILE
    sudo sed -i "s/FTP_PORT = .*/FTP_PORT = $FTP_PORT/" $CONFIG_FILE
    sudo sed -i "s/FTP_USER = .*/FTP_USER = \"$FTP_USER\"/" $CONFIG_FILE
    sudo sed -i "s/FTP_PASS = .*/FTP_PASS = \"$FTP_PASS\"/" $CONFIG_FILE
    sudo sed -i "s/FTP_DIR = .*/FTP_DIR = \"$FTP_DIR\"/" $CONFIG_FILE

    # راه‌اندازی مجدد سرویس
    sudo systemctl restart ftpsub.service

    echo -e "${GREEN}FTP details updated successfully!${NC}"
}

# تابع برای پاک کردن ربات
uninstall_bot() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Bot is not installed. Nothing to uninstall.${NC}"
        return
    fi

    # توقف و غیرفعال‌سازی سرویس
    sudo systemctl stop ftpsub.service
    sudo systemctl disable ftpsub.service
    sudo rm -f $SERVICE_FILE
    sudo systemctl daemon-reload

    # حذف دایرکتوری ربات
    sudo rm -rf $BOT_DIR

    echo -e "${GREEN}Bot uninstalled successfully!${NC}"
}

# منوی اصلی
while true; do
    show_menu
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
            echo -e "${RED}Exiting...${NC}"
            break
            ;;
        *)
            echo -e "${RED}Invalid choice. Please try again.${NC}"
            ;;
    esac

    read -p "Press Enter to continue..."
done
