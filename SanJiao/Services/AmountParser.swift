import Foundation

/// 把中文口语金额解析成元为单位的 Double。
///
/// 支持：
///   - 阿拉伯数字：`18`、`18.5`、`￥18`、`18块`、`18元5角`
///   - 中文数字：`十八`、`两块五`、`一百二十三`、`一百二`(=120)、`一千五`(=1500)
///   - 单位拆解：块/元(整元) · 毛/角(0.1) · 分(0.01) · 半(0.5)
///   - 句中提取：`一杯咖啡十八块`、`打车花了 26 块5`
///
/// 已知边界（交给预览卡兜底，不追求一次对）：
///   - 无任何货币单位、且句中有多个数字时（如「买3个花18」），取最后一个数字。
///   - 不解析日期、不区分收入/支出。
enum AmountParser {

    private static let arabicNum = Set("0123456789.")
    private static let cnDigit: [Character: Int] = [
        "零": 0, "〇": 0,
        "一": 1, "二": 2, "两": 2, "兩": 2, "三": 3, "四": 4,
        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]
    private static let cnUnit: [Character: Int] = ["十": 10, "百": 100, "千": 1000]
    private static let numChars: Set<Character> = {
        var s = arabicNum
        s.formUnion(cnDigit.keys)
        s.formUnion(cnUnit.keys)
        s.insert("万")
        return s
    }()

    static func parse(_ raw: String) -> Double? {
        let s = normalize(raw)
        guard !s.isEmpty else { return nil }

        let hasCurrencyUnit = s.contains(where: { "块元毛角分半".contains($0) })
        if hasCurrencyUnit {
            return parseWithUnits(s)
        }
        return parseBareNumber(s)
    }

    // MARK: - 归一化

    private static func normalize(_ raw: String) -> String {
        var out = ""
        for ch in raw {
            let scalar = ch.unicodeScalars.first!.value
            // 全角数字 ０-９ → 半角
            if scalar >= 0xFF10 && scalar <= 0xFF19 {
                out.append(Character(UnicodeScalar(scalar - 0xFF10 + 0x30)!))
            } else if ch == "．" {
                out.append(".")
            } else if "¥￥$,，、 \t钱".contains(ch) {
                continue
            } else {
                out.append(ch)
            }
        }
        return out
    }

    // MARK: - 单位拆解

    private static func parseWithUnits(_ s: String) -> Double? {
        var yuan = 0.0, jiao = 0.0, fen = 0.0, half = 0.0
        var buf = ""
        var sawUnit = false

        func flushVal() -> Double { numVal(buf) ?? 0 }

        for ch in s {
            if numChars.contains(ch) { buf.append(ch); continue }
            switch ch {
            case "块", "元": yuan = flushVal(); buf = ""; sawUnit = true
            case "毛", "角": jiao = flushVal(); buf = ""; sawUnit = true
            case "分":       fen  = flushVal(); buf = ""; sawUnit = true
            case "半":       half = 0.5;        buf = ""; sawUnit = true
            default:         buf = ""   // 非数字、非单位字符 → 重置缓冲（句中噪音）
            }
        }
        // 尾部残留：「五块五」里 块 之后的 五 没有单位 → 当作角
        if !buf.isEmpty {
            if jiao == 0 { jiao = numVal(buf) ?? 0 }
        }
        _ = sawUnit
        let total = yuan + jiao * 0.1 + fen * 0.01 + half
        return total > 0 ? round(total * 100) / 100 : nil
    }

    // MARK: - 裸数字

    private static func parseBareNumber(_ s: String) -> Double? {
        // 优先阿拉伯数字（取最后一个，口语里金额常在句尾：「买咖啡18」）
        let pattern = "[0-9]+(\\.[0-9]+)?"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(s.startIndex..., in: s)
            let matches = regex.matches(in: s, range: range)
            if let last = matches.last, let r = Range(last.range, in: s) {
                if let v = Double(s[r]), v > 0 { return v }
            }
        }
        // 退回中文数字：取最长的中文数字连续段
        var best = ""
        var cur = ""
        for ch in s {
            if cnDigit[ch] != nil || cnUnit[ch] != nil || ch == "万" {
                cur.append(ch)
                if cur.count > best.count { best = cur }
            } else {
                cur = ""
            }
        }
        if !best.isEmpty, let v = chineseToInt(best), v > 0 { return Double(v) }
        return nil
    }

    // MARK: - 数值转换

    /// 字符串 → Double：阿拉伯（含小数）或中文整数。
    private static func numVal(_ s: String) -> Double? {
        if s.isEmpty { return nil }
        if s.allSatisfy({ arabicNum.contains($0) }) {
            return Double(s)
        }
        if let v = chineseToInt(s) { return Double(v) }
        return nil
    }

    /// 中文数字 → Int（支持 0–99999，含口语省略：一百二=120、一千五=1500）。
    static func chineseToInt(_ s: String) -> Int? {
        guard !s.isEmpty else { return nil }
        var total = 0, section = 0, number = 0, lastUnit = 1
        var consumed = false

        for ch in s {
            if let d = cnDigit[ch] {
                number = d
                consumed = true
            } else if let u = cnUnit[ch] {
                let n = (number == 0) ? 1 : number
                section += n * u
                number = 0
                lastUnit = u
                consumed = true
            } else if ch == "万" {
                section += number
                total += section * 10000
                section = 0; number = 0; lastUnit = 10000
                consumed = true
            } else {
                return nil   // 含非中文数字字符
            }
        }
        // 口语省略：一百「二」→ 末位裸数字按上一单位的 1/10 补足（120、1500）
        if number > 0 && lastUnit >= 100 && section > 0 {
            section += number * (lastUnit / 10)
            number = 0
        }
        total += section + number
        return consumed ? total : nil
    }
}
