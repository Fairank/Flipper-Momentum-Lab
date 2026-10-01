# 文泉驿字库来源

本应用从本仓库 `lib/u8g2/u8g2_fonts.c` 中的 `u8g2_font_wqy12_t_gb2312` 提取所需字形。字形数据逐字节保留，生成器只重建索引、字符数与偏移。源字体摘要及子集大小记录在 `lab_font.h`。

Copyright (C) 2004–2010, WenQuanYi Project Board of Trustees and Qianqian Fang.

字体许可证为 **GPL v2，附字体嵌入例外**。2026-09-24 核对的第一方来源：

- [u8g2 文泉驿字体说明](https://github.com/olikraus/u8g2/wiki/fntgrpwqy)：列出版权、许可证及 BDF 来源。
- [原始 12 像素 BDF 文件](https://github.com/larryli/u8g2_wqy/blob/master/bdf/wenquanyi_9pt.bdf)：文件头标明 WenQuanYi Bitmap Song 0.9.9.8 及同一版权、许可证。
- [GNU GPL version 2 全文](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)。

u8g2 转换后的 C 注释出现 `Copyright: (null)`，这只是缺失的转换元数据，不表示字形属于公有领域。u8g2 库代码及字体转换工具的许可证不替代字形自身的许可证。以上保留上游对字体嵌入例外的声明，不另行扩大授权范围。
