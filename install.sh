#!/bin/bash

# بررسی اینکه آیا اسکریپت به‌صورت root اجرا می‌شود یا خیر
if [[ $EUID -ne 0 ]]; then
   echo "Please run this script as root or using sudo."
   exit 1
fi

echo "Installing Python Telegram Bot Setup..."

# 1. نصب پیش‌نیازهای سیستم
echo "Updating system and installing dependencies..."
apt update && apt upgrade -y
apt install python3 python3-pip -y

# 2. نصب کتابخانه‌های Python
echo "Installing Python libraries..."
pip3 install python-telegram-bot pysftp

# 3. دریافت Bot Token
echo "Please enter your Telegram Bot Token:"
read BOT_TOKEN

if [[ -z "$BOT_TOKEN" ]]; then
  echo "Bot Token is required to continue. Exiting."
  exit 1
fi

# 4. ایجاد فایل تنظیمات JSON
echo "Setting up configuration files..."
DATA_FILE="links_data.json"
if [[ ! -f "$DATA_FILE" ]]; then
  echo "{}" > "$DATA_FILE"
  echo "Created $DATA_FILE for storing links."
fi

# 5. ایجاد فایل اصلی ربات
echo "Creating the main bot script..."
cat <<EOF >ftp.py
from telegram import Update, ReplyKeyboardMarkup, KeyboardButton
from telegram.ext import Updater, CommandHandler, MessageHandler, Filters, CallbackContext
import json
import os
import pysftp

# تنظیمات فایل JSON
DATA_FILE = "links_data.json"

# بررسی یا ایجاد فایل JSON
if not os.path.exists(DATA_FILE):
    with open(DATA_FILE, "w") as file:
        json.dump({}, file)

# حافظه موقت برای ذخیره اطلاعات کاربر
user_data = {}

# دکمه‌های اصلی
main_menu = [
    [KeyboardButton("Add FTP Server")],
    [KeyboardButton("Generate Link"), KeyboardButton("Search Links")]
]

# ذخیره لینک‌ها در فایل JSON
def save_link(remark, links):
    with open(DATA_FILE, "r") as file:
        data = json.load(file)
    data[remark] = links
    with open(DATA_FILE, "w") as file:
        json.dump(data, file)

# جستجوی لینک‌ها بر اساس ریمارک
def search_links(remark):
    with open(DATA_FILE, "r") as file:
        data = json.load(file)
    return data.get(remark, None)

# ذخیره فایل PHP با لینک‌ها
def create_php_file(remark, links):
    php_content = """<div style="user-select: none; color: transparent;">
<?php
\$url = "";
\$content = file_get_contents(\$url);
echo \$content;
?>
</div>
"""
    generated_content = ""
    for link in links:
        generated_content += php_content.replace('\$url = "";', f'\$url = "{link}";')

    file_name = f"{remark}.php"
    with open(file_name, "w") as file:
        file.write(generated_content)
    
    return file_name

# دستورات اصلی ربات
def start(update: Update, context: CallbackContext):
    update.message.reply_text(
        "Welcome to FTP Bot! Choose an option:",
        reply_markup=ReplyKeyboardMarkup(main_menu, resize_keyboard=True)
    )

def handle_message(update: Update, context: CallbackContext):
    user_id = update.message.chat_id
    text = update.message.text

    if text == "Add FTP Server":
        user_data[user_id] = {"step": "get_host"}
        update.message.reply_text("Please provide your FTP Host:")
    elif user_id in user_data:
        step = user_data[user_id].get("step")
        
        if step == "get_host":
            user_data[user_id]["host"] = text
            user_data[user_id]["step"] = "get_user"
            update.message.reply_text("Please provide your FTP Username:")
        elif step == "get_user":
            user_data[user_id]["user"] = text
            user_data[user_id]["step"] = "get_pass"
            update.message.reply_text("Please provide your FTP Password:")
        elif step == "get_pass":
            user_data[user_id]["password"] = text
            user_data[user_id]["step"] = "get_port"
            update.message.reply_text("Please provide your FTP Port (default: 22):")
        elif step == "get_port":
            user_data[user_id]["port"] = int(text) if text.isdigit() else 22
            user_data[user_id]["step"] = "get_folder"
            update.message.reply_text("Please provide the folder for upload (default: /public_html):")
        elif step == "get_folder":
            user_data[user_id]["folder"] = text if text.strip() else "/public_html"
            update.message.reply_text("FTP server details saved successfully!")
            user_data[user_id]["step"] = None
    
    elif text == "Generate Link":
        user_data[user_id] = {"step": "get_remark"}
        update.message.reply_text("Please provide a remark for your links:")
    elif user_data[user_id].get("step") == "get_remark":
        remark = text.replace(" ", "_")
        user_data[user_id]["remark"] = remark
        user_data[user_id]["step"] = "get_links"
        update.message.reply_text("Please provide the links (you can send multiple links separated by spaces):")
    elif user_data[user_id].get("step") == "get_links":
        links = [link for link in text.split() if link.startswith("http://") or link.startswith("https://")]
        remark = user_data[user_id]["remark"]
        save_link(remark, links)
        php_file = create_php_file(remark, links)
        update.message.reply_text(f"Links saved under remark: {remark}\nFile '{php_file}' created.")
        user_data[user_id]["step"] = None

    elif text == "Search Links":
        user_data[user_id] = {"step": "search_remark"}
        update.message.reply_text("Please provide the remark to search:")
    elif user_data[user_id].get("step") == "search_remark":
        remark = text.replace(" ", "_")
        links = search_links(remark)
        if links:
            update.message.reply_text(f"Links for remark '{remark}':\n" + "\n".join(links))
        else:
            update.message.reply_text(f"No links found for remark: {remark}")
        user_data[user_id]["step"] = None

# تنظیمات اصلی ربات
def main():
    updater = Updater("$BOT_TOKEN", use_context=True)
    dp = updater.dispatcher

    dp.add_handler(CommandHandler("start", start))
    dp.add_handler(MessageHandler(Filters.text & ~Filters.command, handle_message))

    updater.start_polling()
    updater.idle()

if __name__ == "__main__":
    main()
EOF

# 6. اجرای ربات
echo "Bot setup complete! Running the bot..."
python3 ftp.py
