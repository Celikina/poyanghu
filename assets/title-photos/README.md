# 开始页照片条的照片来源

开始页右上角的照片条（`scripts/title_photo_carousel.gd`）用这 13 张图。

出处：鄱阳湖国家湿地公园官网「摄影佳作」
http://www.jxpoyanghu.com.cn/lyfw_3/p-12-12.html

原文件由项目协作者提供（`C:\Users\17707\Pictures\poyang`，文件名是随机 UUID），
这里按文件名排序重命名成连号，对照如下：

| 工程内文件名 | 原始文件名 | 尺寸 | 大小 |
| --- | --- | --- | --- |
| title-photo-01.jpg | 0477d27f-64c9-4b13-b8ea-4ca767df47df.jpg | 1000×611 | 267 KB |
| title-photo-02.jpg | 0789da27-caf8-437e-9d3e-c2417c8a60b0.jpg | 1000×750 | 287 KB |
| title-photo-03.jpg | 17c4973a-9096-45c1-ac48-8c9ab20159d6.jpg | 1000×629 | 146 KB |
| title-photo-04.jpg | 1955d0e8-9a90-427f-9e66-348fb65c075f.jpg | 1000×668 | 207 KB |
| title-photo-05.jpg | 2c8db2d0-0979-4e25-98cc-9407471c13c3.jpg | 1000×638 | 249 KB |
| title-photo-06.jpg | 5c4b47b7-4e53-414d-bef5-a33472b95a04.jpg | 1000×662 | 215 KB |
| title-photo-07.jpg | 7ec07263-1b40-48de-bb79-133081c6196d.jpg | 1000×573 | 125 KB |
| title-photo-08.jpg | 8a676b76-d0bb-461d-8b65-d41920be400b.jpg | 1000×711 | 296 KB |
| title-photo-09.jpg | 98e17b4b-255e-4dfa-a4f2-efc6d2dd8fcb.jpg | 1000×660 | 587 KB |
| title-photo-10.jpg | e20cea9b-4d97-43aa-9202-d82ec4f60b0b.jpg | 1000×1000 | 490 KB |
| title-photo-11.jpg | e7411151-88ee-4b81-bd3b-dfeae08cb07f.jpg | 1000×664 | 250 KB |
| title-photo-12.jpg | fdc4a5b9-43e0-4b5f-ad23-9d33bad414ff.jpg | 1000×597 | 203 KB |
| title-photo-13.jpg | ff30673c-7c72-4e67-ac30-f28dcf222ef5.jpg | 1000×701 | 458 KB |

导入设置走引擎默认（`compress/mode=0` 无损、不生成 mipmap），和 `assets/dixinhu.jpg` 一致。
照片只在开始页的 UI 里用；清单写死在 `title_photo_carousel.gd` 的 `PHOTOS` 常量里，
**不扫目录** —— 导出包里 `res://` 只有 `.ctex` 导入产物，扫目录在发行版会扫到 0 张。
