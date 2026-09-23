#import "ORMathText.h"

static NSDictionary *ORLatexSymbols(void)
{
    static NSDictionary *d = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = @{
            // greek
            @"alpha": @"α", @"beta": @"β", @"gamma": @"γ", @"delta": @"δ", @"epsilon": @"ε", @"varepsilon": @"ε",
            @"zeta": @"ζ", @"eta": @"η", @"theta": @"θ", @"vartheta": @"ϑ", @"iota": @"ι", @"kappa": @"κ",
            @"lambda": @"λ", @"mu": @"μ", @"nu": @"ν", @"xi": @"ξ", @"pi": @"π", @"varpi": @"ϖ", @"rho": @"ρ",
            @"varrho": @"ϱ", @"sigma": @"σ", @"varsigma": @"ς", @"tau": @"τ", @"upsilon": @"υ", @"phi": @"φ",
            @"varphi": @"ϕ", @"chi": @"χ", @"psi": @"ψ", @"omega": @"ω",
            @"Gamma": @"Γ", @"Delta": @"Δ", @"Theta": @"Θ", @"Lambda": @"Λ", @"Xi": @"Ξ", @"Pi": @"Π",
            @"Sigma": @"Σ", @"Upsilon": @"Υ", @"Phi": @"Φ", @"Psi": @"Ψ", @"Omega": @"Ω",
            // operators and relations
            @"times": @"×", @"cdot": @"·", @"pm": @"±", @"mp": @"∓", @"div": @"÷", @"ast": @"∗", @"star": @"⋆",
            @"leq": @"≤", @"le": @"≤", @"geq": @"≥", @"ge": @"≥", @"neq": @"≠", @"ne": @"≠", @"approx": @"≈",
            @"equiv": @"≡", @"sim": @"∼", @"simeq": @"≃", @"cong": @"≅", @"propto": @"∝", @"ll": @"≪", @"gg": @"≫",
            @"infty": @"∞", @"sum": @"∑", @"prod": @"∏", @"int": @"∫", @"iint": @"∬", @"oint": @"∮",
            @"sqrt": @"√", @"partial": @"∂", @"nabla": @"∇", @"forall": @"∀", @"exists": @"∃", @"nexists": @"∄",
            @"in": @"∈", @"notin": @"∉", @"ni": @"∋", @"subset": @"⊂", @"supset": @"⊃", @"subseteq": @"⊆",
            @"supseteq": @"⊇", @"cup": @"∪", @"cap": @"∩", @"setminus": @"∖", @"emptyset": @"∅", @"varnothing": @"∅",
            @"land": @"∧", @"lor": @"∨", @"lnot": @"¬", @"neg": @"¬", @"wedge": @"∧", @"vee": @"∨", @"oplus": @"⊕",
            @"otimes": @"⊗", @"perp": @"⊥", @"parallel": @"∥", @"angle": @"∠", @"triangle": @"△", @"circ": @"∘",
            @"bullet": @"•", @"degree": @"°", @"prime": @"′",
            @"rightarrow": @"→", @"to": @"→", @"leftarrow": @"←", @"leftrightarrow": @"↔", @"Rightarrow": @"⇒",
            @"Leftarrow": @"⇐", @"Leftrightarrow": @"⇔", @"implies": @"⇒", @"iff": @"⇔", @"mapsto": @"↦",
            @"uparrow": @"↑", @"downarrow": @"↓", @"longrightarrow": @"⟶", @"longleftarrow": @"⟵",
            @"ldots": @"…", @"cdots": @"⋯", @"dots": @"…", @"vdots": @"⋮", @"ddots": @"⋱",
            @"hbar": @"ℏ", @"ell": @"ℓ", @"Re": @"ℜ", @"Im": @"ℑ", @"aleph": @"ℵ", @"wp": @"℘",
            @"langle": @"⟨", @"rangle": @"⟩", @"lfloor": @"⌊", @"rfloor": @"⌋", @"lceil": @"⌈", @"rceil": @"⌉",
            @"vert": @"|", @"Vert": @"‖", @"mid": @"|", @"backslash": @"\\", @"%": @"%", @"&": @"&", @"#": @"#",
            @"_": @"_", @"{": @"{", @"}": @"}", @"$": @"$",
            @"quad": @"  ", @"qquad": @"    ", @",": @" ", @";": @" ", @":": @" ", @"!": @"", @" ": @" ",
            @"sin": @"sin", @"cos": @"cos", @"tan": @"tan", @"cot": @"cot", @"sec": @"sec", @"csc": @"csc",
            @"arcsin": @"arcsin", @"arccos": @"arccos", @"arctan": @"arctan", @"sinh": @"sinh", @"cosh": @"cosh",
            @"tanh": @"tanh", @"ln": @"ln", @"log": @"log", @"exp": @"exp", @"lim": @"lim", @"max": @"max",
            @"min": @"min", @"sup": @"sup", @"inf": @"inf", @"det": @"det", @"dim": @"dim", @"ker": @"ker",
            @"gcd": @"gcd", @"deg": @"deg", @"arg": @"arg", @"mod": @" mod ", @"bmod": @" mod ", @"pmod": @" mod ",
            @"left": @"", @"right": @"", @"big": @"", @"Big": @"", @"bigg": @"", @"Bigg": @"", @"displaystyle": @"",
            @"textstyle": @"", @"limits": @"", @"nolimits": @"", @"mathrm": @"", @"mathit": @"", @"mathbf": @"",
            @"mathsf": @"", @"mathtt": @"", @"mathcal": @"", @"boldsymbol": @"", @"bm": @"", @"operatorname": @"",
            @"text": @"", @"textrm": @"", @"textit": @"", @"textbf": @"", @"mbox": @"", @"hat": @"", @"bar": @"",
            @"vec": @"", @"tilde": @"", @"dot": @"", @"ddot": @"", @"overline": @"", @"underline": @"",
        };
    });
    return d;
}

static NSDictionary *ORMathbb(void)
{
    return @{ @"R": @"ℝ", @"N": @"ℕ", @"Z": @"ℤ", @"Q": @"ℚ", @"C": @"ℂ", @"P": @"ℙ", @"H": @"ℍ" };
}

static NSString *ORSuperscript(NSString *s)
{
    NSDictionary *map = @{ @"0": @"⁰", @"1": @"¹", @"2": @"²", @"3": @"³", @"4": @"⁴", @"5": @"⁵", @"6": @"⁶", @"7": @"⁷",
                           @"8": @"⁸", @"9": @"⁹", @"+": @"⁺", @"-": @"⁻", @"−": @"⁻", @"=": @"⁼", @"(": @"⁽", @")": @"⁾",
                           @"n": @"ⁿ", @"i": @"ⁱ", @"x": @"ˣ", @"a": @"ᵃ", @"b": @"ᵇ", @"c": @"ᶜ", @"d": @"ᵈ", @"e": @"ᵉ",
                           @"k": @"ᵏ", @"m": @"ᵐ", @"o": @"ᵒ", @"p": @"ᵖ", @"t": @"ᵗ", @"u": @"ᵘ", @"T": @"ᵀ", @" ": @"" };
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < s.length; i++) {
        NSString *c = [s substringWithRange:NSMakeRange(i, 1)];
        NSString *m = map[c];
        if (!m) return nil;
        [out appendString:m];
    }
    return out;
}

static NSString *ORSubscript(NSString *s)
{
    NSDictionary *map = @{ @"0": @"₀", @"1": @"₁", @"2": @"₂", @"3": @"₃", @"4": @"₄", @"5": @"₅", @"6": @"₆", @"7": @"₇",
                           @"8": @"₈", @"9": @"₉", @"+": @"₊", @"-": @"₋", @"−": @"₋", @"=": @"₌", @"(": @"₍", @")": @"₎",
                           @"a": @"ₐ", @"e": @"ₑ", @"o": @"ₒ", @"x": @"ₓ", @"h": @"ₕ", @"k": @"ₖ", @"l": @"ₗ", @"m": @"ₘ",
                           @"n": @"ₙ", @"p": @"ₚ", @"s": @"ₛ", @"t": @"ₜ", @"i": @"ᵢ", @"j": @"ⱼ", @"r": @"ᵣ", @"u": @"ᵤ",
                           @"v": @"ᵥ", @" ": @"" };
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < s.length; i++) {
        NSString *c = [s substringWithRange:NSMakeRange(i, 1)];
        NSString *m = map[c];
        if (!m) return nil;
        [out appendString:m];
    }
    return out;
}

@implementation ORMathText

// Reads a brace group starting at index i (s[i] == '{'); returns the inner text and sets *end after '}'.
+ (NSString *)braceGroupIn:(NSString *)s from:(NSUInteger)i end:(NSUInteger *)end
{
    NSUInteger depth = 0;
    NSUInteger len = s.length;
    for (NSUInteger j = i; j < len; j++) {
        unichar c = [s characterAtIndex:j];
        if (c == '{') depth++;
        else if (c == '}') {
            depth--;
            if (depth == 0) {
                *end = j + 1;
                return [s substringWithRange:NSMakeRange(i + 1, j - i - 1)];
            }
        }
    }
    *end = len;
    return [s substringFromIndex:MIN(i + 1, len)];
}

+ (NSString *)argumentIn:(NSString *)s from:(NSUInteger)i end:(NSUInteger *)end
{
    NSUInteger len = s.length;
    if (i >= len) { *end = i; return @""; }
    unichar c = [s characterAtIndex:i];
    if (c == '{') return [self braceGroupIn:s from:i end:end];
    if (c == '\\') {
        NSUInteger j = i + 1;
        while (j < len && [[NSCharacterSet letterCharacterSet] characterIsMember:[s characterAtIndex:j]]) j++;
        if (j == i + 1) j++;
        *end = j;
        return [self unicodeForLatex:[s substringWithRange:NSMakeRange(i, j - i)]];
    }
    *end = i + 1;
    return [s substringWithRange:NSMakeRange(i, 1)];
}

+ (NSString *)unicodeForLatex:(NSString *)latex
{
    if (!latex.length) return @"";
    NSMutableString *out = [NSMutableString string];
    NSUInteger i = 0, len = latex.length;
    NSDictionary *symbols = ORLatexSymbols();
    while (i < len) {
        unichar c = [latex characterAtIndex:i];
        if (c == '\\') {
            NSUInteger j = i + 1;
            while (j < len && [[NSCharacterSet letterCharacterSet] characterIsMember:[latex characterAtIndex:j]]) j++;
            if (j == i + 1 && j < len) j++;   // single-char control like "\," or "\{"
            NSString *name = [latex substringWithRange:NSMakeRange(i + 1, j - i - 1)];
            NSUInteger end = j;
            if ([name isEqualToString:@"frac"] || [name isEqualToString:@"dfrac"] || [name isEqualToString:@"tfrac"]) {
                NSString *a = [self unicodeForLatex:[self argumentIn:latex from:end end:&end]];
                NSString *b = [self unicodeForLatex:[self argumentIn:latex from:end end:&end]];
                BOOL simple = a.length <= 3 && b.length <= 3;
                [out appendFormat:simple ? @"%@/%@" : @"(%@)/(%@)", a, b];
                i = end;
                continue;
            }
            if ([name isEqualToString:@"sqrt"]) {
                NSString *arg = [self unicodeForLatex:[self argumentIn:latex from:end end:&end]];
                [out appendFormat:arg.length <= 2 ? @"√%@" : @"√(%@)", arg];
                i = end;
                continue;
            }
            if ([name isEqualToString:@"mathbb"]) {
                NSString *arg = [self argumentIn:latex from:end end:&end];
                [out appendString:ORMathbb()[arg] ?: arg];
                i = end;
                continue;
            }
            if ([name isEqualToString:@"text"] || [name isEqualToString:@"mathrm"] || [name isEqualToString:@"textrm"] ||
                [name isEqualToString:@"mathbf"] || [name isEqualToString:@"textbf"] || [name isEqualToString:@"mathit"] ||
                [name isEqualToString:@"operatorname"] || [name isEqualToString:@"mbox"] || [name isEqualToString:@"textit"] ||
                [name isEqualToString:@"mathcal"] || [name isEqualToString:@"boldsymbol"] || [name isEqualToString:@"mathsf"]) {
                NSString *arg = [self argumentIn:latex from:end end:&end];
                [out appendString:[self unicodeForLatex:arg]];
                i = end;
                continue;
            }
            if ([name isEqualToString:@"hat"] || [name isEqualToString:@"vec"] || [name isEqualToString:@"bar"] ||
                [name isEqualToString:@"tilde"] || [name isEqualToString:@"dot"] || [name isEqualToString:@"overline"]) {
                NSString *arg = [self unicodeForLatex:[self argumentIn:latex from:end end:&end]];
                NSString *combining = [name isEqualToString:@"hat"] ? @"̂" : [name isEqualToString:@"vec"] ? @"⃗" :
                                      [name isEqualToString:@"bar"] ? @"̄" : [name isEqualToString:@"tilde"] ? @"̃" :
                                      [name isEqualToString:@"dot"] ? @"̇" : @"̅";
                [out appendString:arg];
                if (arg.length == 1) [out appendString:combining];
                i = end;
                continue;
            }
            NSString *sym = symbols[name];
            [out appendString:sym ?: name];
            i = end;
            // swallow one following space after a word command
            continue;
        }
        if (c == '^' || c == '_') {
            NSUInteger end = i + 1;
            NSString *arg = [self argumentIn:latex from:i + 1 end:&end];
            NSString *inner = [self unicodeForLatex:arg];
            NSString *conv = (c == '^') ? ORSuperscript(inner) : ORSubscript(inner);
            if (conv) [out appendString:conv];
            else [out appendFormat:@"%C(%@)", c, inner];
            i = end;
            continue;
        }
        if (c == '{' || c == '}') { i++; continue; }
        if (c == '~') { [out appendString:@" "]; i++; continue; }
        [out appendFormat:@"%C", c];
        i++;
    }
    return out;
}

#pragma mark - Inline math

// Splits by backtick spans so that code is never touched. `block` receives the plain segments.
+ (NSString *)mapNonCodeSegmentsOf:(NSString *)text with:(NSString *(^)(NSString *segment))block
{
    if ([text rangeOfString:@"`"].location == NSNotFound) return block(text);
    NSMutableString *out = [NSMutableString string];
    NSUInteger i = 0, len = text.length;
    NSMutableString *plain = [NSMutableString string];
    while (i < len) {
        unichar c = [text characterAtIndex:i];
        if (c == '`') {
            NSUInteger ticks = 0;
            while (i + ticks < len && [text characterAtIndex:i + ticks] == '`') ticks++;
            NSString *fence = [@"" stringByPaddingToLength:ticks withString:@"`" startingAtIndex:0];
            NSRange close = [text rangeOfString:fence options:NSLiteralSearch range:NSMakeRange(i + ticks, len - i - ticks)];
            if (close.location != NSNotFound) {
                [out appendString:block(plain)];
                [plain setString:@""];
                [out appendString:[text substringWithRange:NSMakeRange(i, close.location + ticks - i)]];
                i = close.location + ticks;
                continue;
            }
        }
        [plain appendFormat:@"%C", c];
        i++;
    }
    [out appendString:block(plain)];
    return out;
}

+ (NSString *)convertInlineMathIn:(NSString *)text
{
    if (!text.length) return text ?: @"";
    if ([text rangeOfString:@"$"].location == NSNotFound && [text rangeOfString:@"\\("].location == NSNotFound) return text;
    return [self mapNonCodeSegmentsOf:text with:^NSString *(NSString *seg) {
        NSMutableString *out = [NSMutableString string];
        NSUInteger i = 0, len = seg.length;
        while (i < len) {
            unichar c = [seg characterAtIndex:i];
            // \( ... \)
            if (c == '\\' && i + 1 < len && [seg characterAtIndex:i + 1] == '(') {
                NSRange close = [seg rangeOfString:@"\\)" options:NSLiteralSearch range:NSMakeRange(i + 2, len - i - 2)];
                if (close.location != NSNotFound) {
                    [out appendString:[self unicodeForLatex:[seg substringWithRange:NSMakeRange(i + 2, close.location - i - 2)]]];
                    i = close.location + 2;
                    continue;
                }
            }
            // $ ... $ (single dollar, same line, no spaces right after/before the delimiters, not a price)
            if (c == '$' && i + 1 < len && [seg characterAtIndex:i + 1] != '$' && [seg characterAtIndex:i + 1] != ' ') {
                NSUInteger j = i + 1;
                while (j < len) {
                    unichar d = [seg characterAtIndex:j];
                    if (d == '\n') break;
                    if (d == '$' && [seg characterAtIndex:j - 1] != ' ' && [seg characterAtIndex:j - 1] != '\\' &&
                        (j + 1 >= len || ![[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[seg characterAtIndex:j + 1]])) break;
                    j++;
                }
                if (j < len && [seg characterAtIndex:j] == '$' && j > i + 1) {
                    NSString *inner = [seg substringWithRange:NSMakeRange(i + 1, j - i - 1)];
                    // "$5 and $10" style text has digits only and a space inside; leave it alone
                    BOOL looksLikeMath = [inner rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]].location != NSNotFound ||
                                         [inner rangeOfString:@"\\"].location != NSNotFound || [inner rangeOfString:@"^"].location != NSNotFound ||
                                         [inner rangeOfString:@"_"].location != NSNotFound || [inner rangeOfString:@"="].location != NSNotFound;
                    if (looksLikeMath) {
                        [out appendString:[self unicodeForLatex:inner]];
                        i = j + 1;
                        continue;
                    }
                }
            }
            [out appendFormat:@"%C", c];
            i++;
        }
        return out;
    }];
}

#pragma mark - HTML cleanup

+ (NSString *)cleanupHTMLIn:(NSString *)text
{
    if (!text.length) return text ?: @"";
    if ([text rangeOfString:@"<"].location == NSNotFound && [text rangeOfString:@"&"].location == NSNotFound) return text;
    return [self mapNonCodeSegmentsOf:text with:^NSString *(NSString *seg) {
        NSMutableString *s = [seg mutableCopy];
        NSRegularExpression *br = [NSRegularExpression regularExpressionWithPattern:@"<br\\s*/?>" options:NSRegularExpressionCaseInsensitive error:NULL];
        [br replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"\n"];
        NSRegularExpression *bold = [NSRegularExpression regularExpressionWithPattern:@"</?(b|strong)>" options:NSRegularExpressionCaseInsensitive error:NULL];
        [bold replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"**"];
        NSRegularExpression *ital = [NSRegularExpression regularExpressionWithPattern:@"</?(i|em)>" options:NSRegularExpressionCaseInsensitive error:NULL];
        [ital replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"*"];
        NSRegularExpression *code = [NSRegularExpression regularExpressionWithPattern:@"</?code>" options:NSRegularExpressionCaseInsensitive error:NULL];
        [code replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"`"];
        NSRegularExpression *strip = [NSRegularExpression regularExpressionWithPattern:@"</?(sup|sub|u|span|div|p|font|small|big|kbd|s|del|ins|mark|center)( [^>]*)?>" options:NSRegularExpressionCaseInsensitive error:NULL];
        [strip replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@""];
        NSDictionary *entities = @{ @"&nbsp;": @" ", @"&amp;": @"&", @"&lt;": @"<", @"&gt;": @">", @"&quot;": @"\"", @"&#39;": @"'",
                                    @"&apos;": @"'", @"&hellip;": @"…", @"&mdash;": @"—", @"&ndash;": @"–", @"&times;": @"×",
                                    @"&deg;": @"°", @"&le;": @"≤", @"&ge;": @"≥", @"&ne;": @"≠", @"&rarr;": @"→", @"&larr;": @"←" };
        for (NSString *k in entities) [s replaceOccurrencesOfString:k withString:entities[k] options:NSCaseInsensitiveSearch range:NSMakeRange(0, s.length)];
        return s;
    }];
}

@end
