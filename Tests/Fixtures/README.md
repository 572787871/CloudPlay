本目录视频由 FFmpeg 的 testsrc2 和 sine 信号源自行生成，无第三方影片。
MP4：320×180、H.264、AAC，8 秒；MKV：相同音视频与自生成 SRT 内嵌字幕。
用于自动测试真实播放器准备、时间推进及 Seek。该测试不能代替 iPhone 画面、音频输出或硬件解码验证。

生成命令：

```sh
ffmpeg -f lavfi -i testsrc2=size=320x180:rate=15 -f lavfi -i sine=frequency=440:sample_rate=44100 -t 8 -c:v libx264 -preset fast -crf 30 -pix_fmt yuv420p -c:a aac -b:a 48k -movflags +faststart generated.mp4
ffmpeg -i generated.mp4 -i generated.srt -map 0:v -map 0:a -map 1:0 -c copy -c:s srt generated.mkv
```
