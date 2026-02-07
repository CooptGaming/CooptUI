#!/usr/bin/env python3
"""
EverQuest Epic Quest Data Scraper
Scrapes epic quest information from Project 1999 Wiki and Almar's Guides
"""

import requests
from bs4 import BeautifulSoup
import json
import re
import time
from urllib.parse import urljoin, urlparse
from typing import Dict, List, Optional, Tuple

# Epic quest URLs from Project 1999 Wiki
P99_EPIC_URLS = {
    'bard': 'https://wiki.project1999.com/Bard_Epic_Quest',
    'cleric': 'https://wiki.project1999.com/Cleric_Epic_Quest',
    'druid': 'https://wiki.project1999.com/Druid_Epic_Quest',
    'enchanter': 'https://wiki.project1999.com/Enchanter_Epic_Quest',
    'magician': 'https://wiki.project1999.com/Magician_Epic_Quest',
    'monk': 'https://wiki.project1999.com/Monk_Epic_Quest',
    'necromancer': 'https://wiki.project1999.com/Necromancer_Epic_Quest',
    'paladin': 'https://wiki.project1999.com/Paladin_Epic_Quest',
    'ranger': 'https://wiki.project1999.com/Ranger_Epic_Quest',
    'rogue': 'https://wiki.project1999.com/Rogue_Epic_Quest',
    'shadowknight': 'https://wiki.project1999.com/Shadow_Knight_Epic_Quest',
    'shaman': 'https://wiki.project1999.com/Shaman_Epic_Quest',
    'warrior': 'https://wiki.project1999.com/Warrior_Epic_Quest',
    'wizard': 'https://wiki.project1999.com/Wizard_Epic_Quest',
}

# Almar's Guides URLs
ALMAR_EPIC_URLS = {
    'bard': 'https://www.almarsguides.com/eq/epics/bard1.0.cfm',
    'cleric': 'https://www.almarsguides.com/eq/epics/cleric1.0.cfm',
    'druid': 'https://www.almarsguides.com/eq/epics/druid1.0.cfm',
    'enchanter': 'https://www.almarsguides.com/eq/epics/enchanter1.0.cfm',
    'magician': 'https://www.almarsguides.com/eq/epics/mage1.0.cfm',
    'monk': 'https://www.almarsguides.com/eq/epics/monk1.0.cfm',
    'necromancer': 'https://www.almarsguides.com/eq/epics/necromancer1.0.cfm',
    'paladin': 'https://www.almarsguides.com/eq/epics/paladin1.0.cfm',
    'ranger': 'https://www.almarsguides.com/eq/epics/ranger1.0.cfm',
    'rogue': 'https://www.almarsguides.com/eq/epics/rogue1.0.cfm',
    'shadowknight': 'https://www.almarsguides.com/eq/epics/shadowknight1.0.cfm',
    'shaman': 'https://www.almarsguides.com/eq/epics/shaman1.0.cfm',
    'warrior': 'https://www.almarsguides.com/eq/epics/warrior1.0.cfm',
    'wizard': 'https://www.almarsguides.com/eq/epics/wizard1.0.cfm',
}

def fetch_url(url: str, retries: int = 3) -> Optional[str]:
    """Fetch URL content with retries"""
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    }
    for attempt in range(retries):
        try:
            response = requests.get(url, headers=headers, timeout=30)
            response.raise_for_status()
            return response.text
        except Exception as e:
            print(f"Attempt {attempt + 1} failed for {url}: {e}")
            if attempt < retries - 1:
                time.sleep(2 ** attempt)
    return None

def parse_coordinates(text: str) -> Optional[Dict[str, float]]:
    """Extract coordinates from text like 'loc(-516, -2434)' or '+380, -210'"""
    # Pattern for loc(x, y) format
    loc_pattern = r'loc\(([+-]?\d+(?:\.\d+)?),\s*([+-]?\d+(?:\.\d+)?)\)'
    match = re.search(loc_pattern, text, re.IGNORECASE)
    if match:
        return {'x': float(match.group(1)), 'y': float(match.group(2))}
    
    # Pattern for +x, -y format
    coord_pattern = r'([+-]?\d+(?:\.\d+)?)\s*,\s*([+-]?\d+(?:\.\d+)?)'
    matches = re.findall(coord_pattern, text)
    if matches:
        # Take first match
        return {'x': float(matches[0][0]), 'y': float(matches[0][1])}
    
    return None

def extract_item_info(text: str) -> List[Dict]:
    """Extract item names and details from text"""
    items = []
    # Look for item names in brackets or quotes
    item_pattern = r'\[([^\]]+)\]|"([^"]+)"|([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)'
    # This is a simplified version - will need refinement
    return items

def parse_p99_epic_page(html: str, class_name: str) -> Dict:
    """Parse Project 1999 epic quest page"""
    soup = BeautifulSoup(html, 'html.parser')
    
    quest_data = {
        'class': class_name,
        'source': 'project1999',
        'reward': {},
        'steps': [],
        'items': [],
        'npcs': [],
        'zones': [],
        'mobs': []
    }
    
    # Extract reward information
    reward_section = soup.find('h2', string=re.compile('Reward', re.I))
    if reward_section:
        reward_link = reward_section.find_next('a')
        if reward_link:
            quest_data['reward']['name'] = reward_link.get_text().strip()
            quest_data['reward']['url'] = reward_link.get('href', '')
    
    # Extract checklist/steps
    checklist = soup.find('h2', string=re.compile('Checklist|Walkthrough', re.I))
    if checklist:
        # Find all list items or steps
        steps_section = checklist.find_next(['ul', 'ol', 'div'])
        if steps_section:
            steps = steps_section.find_all(['li', 'p'], recursive=False)
            for step in steps:
                step_text = step.get_text().strip()
                if step_text:
                    quest_data['steps'].append({
                        'text': step_text,
                        'raw_html': str(step)
                    })
    
    # Extract zones mentioned
    zone_links = soup.find_all('a', href=re.compile('/Zones/|/Category:Zones'))
    zones = set()
    for link in zone_links:
        zone_name = link.get_text().strip()
        if zone_name:
            zones.add(zone_name)
    quest_data['zones'] = list(zones)
    
    return quest_data

def parse_almar_epic_page(html: str, class_name: str) -> Dict:
    """Parse Almar's Guides epic quest page"""
    soup = BeautifulSoup(html, 'html.parser')
    
    quest_data = {
        'class': class_name,
        'source': 'almarsguides',
        'steps': [],
        'items': [],
        'npcs': [],
        'zones': [],
        'mobs': []
    }
    
    # Almar's guides typically have checklist format
    checklist_items = soup.find_all(['li', 'p'])
    for item in checklist_items:
        text = item.get_text().strip()
        if text and ('(' in text or ')' in text):  # Likely a checklist item
            quest_data['steps'].append({
                'text': text,
                'raw_html': str(item)
            })
    
    return quest_data

def scrape_all_epics():
    """Scrape all epic quests from both sources"""
    all_epics = {}
    
    print("Scraping Project 1999 Wiki...")
    for class_name, url in P99_EPIC_URLS.items():
        print(f"  Fetching {class_name} epic...")
        html = fetch_url(url)
        if html:
            epic_data = parse_p99_epic_page(html, class_name)
            if class_name not in all_epics:
                all_epics[class_name] = {}
            all_epics[class_name]['p99'] = epic_data
        time.sleep(1)  # Be polite
    
    print("\nScraping Almar's Guides...")
    for class_name, url in ALMAR_EPIC_URLS.items():
        print(f"  Fetching {class_name} epic...")
        html = fetch_url(url)
        if html:
            epic_data = parse_almar_epic_page(html, class_name)
            if class_name not in all_epics:
                all_epics[class_name] = {}
            all_epics[class_name]['almar'] = epic_data
        time.sleep(1)  # Be polite
    
    return all_epics

if __name__ == '__main__':
    print("Starting epic quest scraper...")
    epics = scrape_all_epics()
    
    # Save raw data
    with open('../data/epic_quests_raw.json', 'w', encoding='utf-8') as f:
        json.dump(epics, f, indent=2, ensure_ascii=False)
    
    print(f"\nScraped {len(epics)} epic quests")
    print("Raw data saved to ../data/epic_quests_raw.json")
