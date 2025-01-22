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
    """تولید محتوای PHP"""
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
