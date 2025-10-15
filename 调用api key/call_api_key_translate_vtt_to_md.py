import os
import requests
import json
import webvtt
import tiktoken
import time
import re

# --- 1. 配置区 ---

VTT_FOLDER_PATH = r'C:\Users\wwd_m\Downloads\test-vtt'
OUTPUT_FOLDER_PATH = r'C:\Users\wwd_m\Downloads\output-vtt-md'

# --- 【请在这里修改为您的API配置】 ---

# 1. API URL (请根据您使用的服务商取消注释并使用)
# OpenAI (GPT系列)
# API_URL = 'https://api.openai.com/v1/chat/completions'
# DeepSeek (与OpenAI格式兼容)
# API_URL = 'https://api.deepseek.com/chat/completions'
# Google (Gemini系列) - 注意：URL中需要包含模型名称和 :generateContent
API_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent'


# 2. API KEY
# 【重要】请将 "..." 替换为您的真实 API Key
API_KEY = '' # 替换为您的 Gemini API Key

# 3. 模型名称 (Model Name)
# OpenAI Models
# MODEL_NAME = 'gpt-4o'
# DeepSeek Models
# MODEL_NAME = 'deepseek-chat'
# Google Gemini Models - 在Gemini中，此变量仅作参考，实际模型在URL中指定
MODEL_NAME = 'gemini-2.0-flash' 

# --- 【API配置结束】 ---

MAX_TOKENS_PER_CHUNK = 16000 

SYSTEM_PROMPT = """
你是一位顶级的翻译家和内容编辑。
你的任务是：将用户提供的英文视频口播稿，完整地翻译成一篇流畅、自然、连贯的简体中文文章。

请严格遵守以下核心原则：
1. **全文翻译与合并**：
   - 必须逐句翻译所有内容，不能省略或总结。
   - **关键指令**：请智能地将原文中语义连贯的多行短句，合并成符合中文阅读习惯的自然段落。不要原文每行都换行。

2. **保持逻辑**：在合并段落时，要尊重原文的逻辑停顿。如果原文有明显的空行或意群转换，可以在译文中也进行分段。

3. **Markdown输出**：使用 Markdown 格式，可以对关键词进行 **加粗** 以提高可读性。

4. **直接输出文章**：请直接开始输出最终翻译好的中文文章，不要包含任何解释或类似 <think> 的标签。
"""

# --- 2. 核心功能区 (其余函数不变) ---

def get_tokenizer():
    try:
        return tiktoken.get_encoding("cl100k_base")
    except Exception as e:
        print(f"获取 tokenizer 失败: {e}")
        return None

def parse_vtt_file(file_path):
    try:
        captions = webvtt.read(file_path)
        full_text = "\n".join([caption.text.strip() for caption in captions])
        return full_text
    except Exception as e:
        print(f"解析VTT文件 {os.path.basename(file_path)} 时出错: {e}")
        return None

def split_text_into_chunks(text, tokenizer):
    if not tokenizer:
        print("Tokenizer 不可用，无法进行分片。将尝试一次性处理。")
        return [text]
    tokens = tokenizer.encode(text)
    if len(tokens) <= MAX_TOKENS_PER_CHUNK:
        print(f"文本长度为 {len(tokens)} tokens，小于阈值 {MAX_TOKENS_PER_CHUNK}，将一次性处理。")
        return [text]
    print(f"文本过长 ({len(tokens)} tokens)，正在分片处理...")
    chunks = []
    current_chunk_tokens = []
    paragraphs = text.split('\n')
    for paragraph in paragraphs:
        if not paragraph.strip():
            continue
        paragraph_tokens = tokenizer.encode(paragraph + "\n")
        if len(current_chunk_tokens) + len(paragraph_tokens) > MAX_TOKENS_PER_CHUNK:
            if current_chunk_tokens:
                chunks.append(tokenizer.decode(current_chunk_tokens))
                current_chunk_tokens = []
        current_chunk_tokens.extend(paragraph_tokens)
    if current_chunk_tokens:
        chunks.append(tokenizer.decode(current_chunk_tokens))
    print(f"文本成功被分成了 {len(chunks)} 个片段。")
    return chunks

def clean_model_output(raw_text):
    cleaned_text = re.sub(r'^\s*<think>.*?</think>\s*', '', raw_text, flags=re.DOTALL)
    return cleaned_text

# --- 【重大修改】支持多服务商API的函数 ---
def process_chunk_with_llm(text_chunk):
    headers = {"Content-Type": "application/json"}
    payload = {}
    url = API_URL
    
    # --- 根据API_URL判断是哪个服务商 ---
    
    # 1. 如果是 Google Gemini API
    if "generativelanguage.googleapis.com" in API_URL:
        # Gemini 的 URL 需要拼接 API Key
        url = f"{API_URL}?key={API_KEY}"
        # Gemini 的 Payload 结构
        # 注意: Gemini 没有明确的 "system" role, 通常将系统指令作为对话的第一个 "user" message
        payload = {
            "contents": [
                {"role": "user", "parts": [{"text": SYSTEM_PROMPT}]},
                {"role": "model", "parts": [{"text": "好的，我明白了。请给我需要翻译的英文口播稿。"}]}, # 模拟一个对话轮次，让模型进入角色
                {"role": "user", "parts": [{"text": text_chunk}]}
            ]
        }
        
    # 2. 如果是 OpenAI 或 兼容OpenAI 的 API (如 DeepSeek)
    else:
        # OpenAI 的认证信息在请求头
        headers["Authorization"] = f"Bearer {API_KEY}"
        # OpenAI 的 Payload 结构
        payload = {
            "model": MODEL_NAME,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": text_chunk}
            ],
            "temperature": 0.7,
            "stream": False
        }

    # --- 发送请求并处理响应 ---
    try:
        response = requests.post(url, headers=headers, data=json.dumps(payload), timeout=300)
        response.raise_for_status()
        response_json = response.json()
        
        raw_output_text = ""
        # 根据不同服务商的响应格式提取内容
        if "generativelanguage.googleapis.com" in API_URL:
            # Gemini 的响应路径
            raw_output_text = response_json['candidates'][0]['content']['parts'][0]['text']
        else:
            # OpenAI 的响应路径
            raw_output_text = response_json['choices'][0]['message']['content']
            
        cleaned_output_text = clean_model_output(raw_output_text)
        return cleaned_output_text
        
    except requests.exceptions.Timeout:
        print(f"调用API时超时！(超过300秒)")
        return None
    except requests.exceptions.RequestException as e:
        error_message = f"调用API时出错: {e}"
        if e.response is not None:
            error_message += f"\n服务器响应状态码: {e.response.status_code}"
            try:
                error_message += f"\n服务器响应内容: {e.response.text}"
            except Exception:
                error_message += "\n(无法解析服务器响应内容)"
        print(error_message)
        return None

def process_single_file(vtt_file_path, tokenizer):
    filename = os.path.basename(vtt_file_path)
    print(f"\n--- 正在处理文件: {filename} ---")
    
    english_text = parse_vtt_file(vtt_file_path)
    if not english_text:
        return

    chunks = split_text_into_chunks(english_text, tokenizer)
    
    processed_chunks = []
    for i, chunk in enumerate(chunks):
        if len(chunks) > 1:
            print(f"正在翻译片段 {i+1}/{len(chunks)}...")
        
        translated_chunk = process_chunk_with_llm(chunk)
        if not translated_chunk:
            print(f"翻译失败，已跳过整个文件 {filename}。")
            return
        processed_chunks.append(translated_chunk)
        if len(chunks) > 1:
            time.sleep(1)
        
    final_text = "\n\n".join(processed_chunks)
    output_filename = f"{os.path.splitext(filename)[0]}.md"
    output_file_path = os.path.join(OUTPUT_FOLDER_PATH, output_filename)
    try:
        with open(output_file_path, 'w', encoding='utf-8') as f:
            f.write(final_text.strip())
        print(f"处理完成！翻译稿已保存至: {output_file_path}\n" + "-"*40)
    except IOError as e:
        print(f"保存文件 {output_filename} 时出错: {e}")

# --- 3. 主程序入口 ---
def main():
    if not API_KEY or API_KEY == '...':
        print("错误：请在代码的配置区填写您的 API_KEY。")
        return
        
    if not os.path.isdir(VTT_FOLDER_PATH):
        print(f"错误：输入文件夹路径不存在 -> {VTT_FOLDER_PATH}")
        return
    if not os.path.isdir(OUTPUT_FOLDER_PATH):
        try:
            os.makedirs(OUTPUT_FOLDER_PATH)
            print(f"已自动创建输出文件夹: {OUTPUT_FOLDER_PATH}")
        except OSError as e:
            print(f"错误：无法创建输出文件夹 {OUTPUT_FOLDER_PATH}。错误信息: {e}")
            return
            
    tokenizer = get_tokenizer()
    for filename in sorted(os.listdir(VTT_FOLDER_PATH)):
        if filename.lower().endswith(".vtt"):
            vtt_file_path = os.path.join(VTT_FOLDER_PATH, filename)
            process_single_file(vtt_file_path, tokenizer)

if __name__ == '__main__':
    main()