import yt_dlp
import os

# ==================== 配置区 (请在这里修改) ====================

# 1. 填入你想要下载的 YouTube 频道的 "Videos" 页面 URL
CHANNEL_URL = "https://www.youtube.com/@marktilbury"

# 2. 定义存放最终字幕文件的输出文件夹名
OUTPUT_DIR = 'output_result'

# 3. 定义 Cookies 文件名 (用于登录验证)
COOKIE_FILE = 'www.youtube.com_cookies.txt'

# 4. 定义临时存放 URL 列表的文件名 (脚本会自动创建和覆盖)
URLS_FILE = 'urls.txt'

# =============================================================

def get_channel_video_urls(channel_url):
    """
    使用 yt-dlp 获取一个频道下的所有视频 URL。
    这相当于命令: yt-dlp --flat-playlist --print url "channel_url"
    """
    ydl_opts = {
        'extract_flat': True,  # 等同于 --flat-playlist，只提取链接，不访问视频详情
        'quiet': True,         # 不在控制台打印过多信息
    }
    
    video_urls = []
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            # extract_info 会返回一个包含所有信息的字典
            result = ydl.extract_info(channel_url, download=False)
            
            if 'entries' in result:
                # 从返回结果中提取每个视频的 URL
                video_urls = [entry['url'] for entry in result['entries']]
    except Exception as e:
        print(f"错误：获取频道视频列表失败。请检查 URL 是否正确以及网络连接。")
        print(f"详细错误: {e}")
        return None
        
    return video_urls

def download_subtitles_from_list(urls):
    """
    根据给定的 URL 列表，下载所有视频的字幕。
    """
    # 配置 yt-dlp 的下载选项
    ydl_opts = {
        'writesubtitles': True,
        'writeautomaticsub': True,
        'subtitleslangs': ['en', 'zh-CN', 'zh-Hant'],
        'skip_download': True,
        'ignoreerrors': True,
        'outtmpl': os.path.join(OUTPUT_DIR, '%(title)s.%(ext)s'),
        'cookiefile': COOKIE_FILE,
        
        # 添加禁止写入额外文件的选项，保持输出目录干净
        'writedescription': False,
        'writeinfojson': False,
        'writethumbnail': False,
    }

    # 使用 yt-dlp 的 Python API 开始下载
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        total_urls = len(urls)
        for i, url in enumerate(urls, 1):
            print(f"--- [进度: {i}/{total_urls}] 正在处理URL: {url} ---")
            try:
                ydl.download([url])
                print("字幕下载成功。")
            except Exception as e:
                print(f"处理过程中发生错误: {e}")

def main():
    """
    主函数：集成所有步骤，实现完全自动化。
    """
    print("============================================")
    print("YouTube 频道字幕下载器")
    print("============================================")

    # 步骤 1: 获取频道下的所有视频 URL
    print(f"\n[步骤 1/3] 正在从频道获取所有视频的 URL 列表...\n频道: {CHANNEL_URL}")
    video_urls = get_channel_video_urls(CHANNEL_URL)

    if not video_urls:
        print("\n无法获取视频列表，脚本已终止。")
        return

    print(f"成功获取到 {len(video_urls)} 个视频 URL。")

    # 步骤 2: 将获取到的 URL 写入 urls.txt 文件
    try:
        with open(URLS_FILE, 'w', encoding='utf-8') as f:
            for url in video_urls:
                f.write(f"{url}\n")
        print(f"\n[步骤 2/3] 已将所有 URL 成功写入文件 '{URLS_FILE}'。")
    except Exception as e:
        print(f"\n错误：无法写入 URL 文件。详细错误: {e}")
        return

    # 步骤 3: 创建输出文件夹并开始下载字幕
    if not os.path.exists(OUTPUT_DIR):
        print(f"输出文件夹 '{OUTPUT_DIR}' 不存在，正在创建...")
        os.makedirs(OUTPUT_DIR)
        
    print(f"\n[步骤 3/3] 开始根据 '{URLS_FILE}' 中的列表下载字幕...")
    download_subtitles_from_list(video_urls)

    print(f"\n所有任务处理完毕！下载的字幕文件已全部保存在 '{OUTPUT_DIR}' 文件夹中。")

# 当直接运行此脚本文件时，执行 main() 函数
if __name__ == '__main__':
    main()