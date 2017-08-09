import std.path : buildPath;
import std.file : DirEntry, SpanMode, dirEntries, exists, isDir, mkdirRecurse, write, readText;
import std.regex : regex, matchAll;
import std.string : toStringz, format;
import std.conv : to;
import std.json : JSONValue;
import std.csv : csvReader;
import std.math : PI, sqrt, abs, sin, cos, acos;
import std.random : Random, uniform;
import std.array : replicate;
import std.algorithm.searching : canFind, findSplitBefore;
import std.algorithm.sorting : sort;
import std.algorithm.comparison : max;

import derelict.freeimage.freeimage;

import dlangui.platforms.common.startup : initResourceManagers, initFontManager;
import dlangui.graphics.drawbuf : ColorDrawBuf;
import dlangui.graphics.fonts : Font, FontManager, FontWeight, FontFamily;

enum ICON_SIZE = 64;

enum MAX_NAME_LENGTH = 12;

enum REPO_USER = "DDoS";
enum REPO_NAME = "sprite-icons";
enum GH_REPO_RAW_FORMAT = "https://raw.githubusercontent.com/" ~ REPO_USER ~ "/"
        ~ REPO_NAME ~ "/master/%s";

alias IconPixels = Pixel[ICON_SIZE ^^ 2];

struct Pixel {
    float r = 0;
    float g = 0;
    float b = 0;
    float a = 0;

    alias h = r;
    alias s = g;
    alias v = b;

    this(int r, int g, int b, int a = ubyte.max) {
        this.r = cast(float) (r & 0xFF) / ubyte.max;
        this.g = cast(float) (g & 0xFF) / ubyte.max;
        this.b = cast(float) (b & 0xFF) / ubyte.max;
        this.a = cast(float) (a & 0xFF) / ubyte.max;
    }

    this(float r, float g, float b, float a = 1) {
        this.r = r;
        this.g = g;
        this.b = b;
        this.a = a;
    }

    @property
    ubyte toUbyte(string comp)() {
        auto c = mixin("this." ~ comp) * 255;
        if (c < ubyte.min) {
            return ubyte.min;
        }
        if (c > ubyte.max) {
            return ubyte.max;
        }
        return cast(ubyte) c;
    }

    Pixel opBinary(string op)(Pixel that)
            if (op == "+" || op == "-" || op == "*" || op == "/" || op == "%") {
        auto rn = mixin("this.r " ~ op ~ " that.r");
        auto gn = mixin("this.g " ~ op ~ " that.g");
        auto bn = mixin("this.b " ~ op ~ " that.b");
        auto an = mixin("this.a " ~ op ~ " that.a");
        return Pixel(rn, gn, bn, an);
    }

    Pixel opBinary(string op)(float factor)
            if (op == "+" || op == "-" || op == "*" || op == "/" || op == "%") {
        auto rn = mixin("this.r " ~ op ~ " factor");
        auto gn = mixin("this.g " ~ op ~ " factor");
        auto bn = mixin("this.b " ~ op ~ " factor");
        auto an = mixin("this.a " ~ op ~ " factor");
        return Pixel(rn, gn, bn, an);
    }

    Pixel opOpAssign(string op)(Pixel that) {
        this = mixin("this " ~ op ~ " that");
        return this;
    }

    Pixel opOpAssign(string op)(float factor) {
        this = mixin("this " ~ op ~ " factor");
        return this;
    }

    float dot(Pixel that) {
        return this.r * that.r + this.g * that.g + this.b * that.b + this.a * that.a;
    }

    @property
    float norm() {
        return this.dot(this).sqrt();
    }
}

void main(string[] args) {
    assert(args.length == 3);

    DerelictFI.load();

    auto sourceDir = args[1];
    auto outputDir = args[2];

    assert (sourceDir.exists() && sourceDir.isDir());
    if (!outputDir.exists()) {
        outputDir.mkdirRecurse();
    }

    createMinimalIcons(sourceDir, outputDir);
}

void createIcons(string sourceDir, string outputDir) {
    string[size_t] idToFile;

    void convertIcon(size_t id, ref IconPixels icon) {
        makeTransparent(icon);
        idToFile[id] = saveIcon(id, icon, outputDir);
    }

    sourceDir.buildPath("GenI").processGenIcons!convertIcon();
    sourceDir.buildPath("GenII").processGenIcons!convertIcon();
    //sourceDir.buildPath("GenIII").processGenIcons!convertIcon();

    foreach (i; 1 .. 252) {
        if (i !in idToFile) {
            throw new Exception(format("Missing ID: %d", i));
        }
    }

    auto json = createJson(idToFile);
    outputDir.buildPath("icons.json").write(json);
}

void createMinimalIcons(string sourceDir, string outputDir) {
    auto nameById = loadPokemonNames();
    initResourceManagers();
    initFontManager();

    auto font = FontManager.instance.getFont(24, FontWeight.Bold, false, FontFamily.SansSerif, "Ubuntu Mono");
    auto maxTextSize = font.textSize("A"d.replicate(MAX_NAME_LENGTH / 2));
    auto squareSize = max(maxTextSize.x, maxTextSize.y);
    auto margin = cast(int) (squareSize * 0.1);
    auto iconSize = squareSize + margin * 2;

    string[size_t] idToFile;

    void convertIcon(size_t id, ref IconPixels icon) {
        makeTransparent(icon);
        Pixel colourA, colourB;
        findPrimaryColourPair(id, icon, colourA, colourB);
        auto minimalIcon = createMinimalIcon(id, nameById[id], font, colourA, colourB, iconSize, margin);
        idToFile[id] = saveIcon(id, minimalIcon, iconSize, outputDir);
    }

    sourceDir.buildPath("GenI").processGenIcons!convertIcon();
    sourceDir.buildPath("GenII").processGenIcons!convertIcon();
    //sourceDir.buildPath("GenIII").processGenIcons!convertIcon();

    foreach (i; 1 .. 252) {
        if (i !in idToFile) {
            throw new Exception(format("Missing ID: %d", i));
        }
    }

    auto json = createJson(idToFile);
    outputDir.buildPath("icons.json").write(json);
}

void processGenIcons(alias processor)(string sourceDir) {
    auto numberedImage = regex(r"(\d+)\.png");

    foreach (DirEntry file; dirEntries(sourceDir, SpanMode.shallow)) {
        if (!file.isFile) {
            continue;
        }

        auto numberText = file.name.matchAll(numberedImage);
        if (numberText.empty()) {
            continue;
        }
        auto number = to!size_t(numberText.front[1]);
        numberText.popFront();
        assert (numberText.empty);

        IconPixels icon;
        loadIcon(file, icon);
        processor(number, icon);
    }
}

void makeTransparent(ref IconPixels icon) {
    // We'll asume that the bottom right corner is always a background pixel
    auto transparent = icon[0];
    foreach (i; 0 .. ICON_SIZE ^^ 2) {
        if (icon[i] == transparent) {
            icon[i].a = 0;
        }
    }
}

void findPrimaryColourPair(size_t id, ref IconPixels icon, ref Pixel colourA, ref Pixel colourB) {
    struct Bucket {
        Pixel colour;
        int count;
    }
    enum maxBuckets = 16;
    Bucket[maxBuckets] buckets;
    auto bucketCount = 0;
    auto colourTotal = 0;
    foreach (i; 0 .. ICON_SIZE ^^ 2) {
        auto pixel = icon[i];
        if (pixel.a == 0) {
            // Skip transparent pixels
            continue;
        }
        // Search for the colour in an existing bucket
        size_t minIndex = -1;
        auto minDist = float.max;
        foreach (j, bucket; buckets[0 .. bucketCount]) {
            auto dist = (bucket.colour - pixel).norm;
            if (dist < minDist) {
                minIndex = j;
                minDist = dist;
            }
        }
        // If an exact match is found, then increment that bucket
        if (minDist == 0) {
            buckets[minIndex].count += 1;
        } else if (bucketCount < maxBuckets) {
            // Otherwise place it in new bucket if at least one is free
            buckets[bucketCount].colour = pixel;
            buckets[bucketCount].count += 1;
            bucketCount += 1;
        } else {
            // Otherwise use the closest bucket
            buckets[minIndex].count += 1;
        }
        colourTotal += 1;
    }
    // Penalize blacks by cutting their counts by a fixed percent, to effectively ignore outlines
    enum maxColourNorm = Pixel(ubyte.max, ubyte.max, ubyte.max, ubyte.max).norm;
    foreach (ref bucket; buckets[0 .. bucketCount]) {
        if (bucket.colour.norm < maxColourNorm * 0.55f) {
            bucket.count = bucket.count / 16;
        }
    }
    // Sort colours by decending occurence
    buckets[].sort!"a.count > b.count"();
    // Shouldn't happen
    if (bucketCount < 2) {
        assert (0, "what");
    }
    // If there's only two colours, then they are the two primary ones
    if (bucketCount == 2) {
        colourA = buckets[0].colour;
        colourB = buckets[1].colour;
        return;
    }
    // Use the most use colour for the first
    colourA = buckets[0].colour;
    // Ignore the least used colours
    Bucket[] bestBuckets;
    foreach (bucket; buckets[0 .. bucketCount]) {
        if (cast(float) bucket.count / colourTotal >= 0.02f) {
            bestBuckets ~= bucket;
        }
    }
    // Pick a second colour, with the most hue difference
    auto hsvA = colourA.rgb2hsv();
    auto maxDiff = -1f;
    size_t maxIndex = 1;
    foreach (i, bucket; bestBuckets) {
        auto hsvC = bucket.colour.rgb2hsv();
        // If the first colour has low value then avoid colours with even lower values
        if (hsvA.v < 0.2f && hsvC.v < hsvA.v + 0.1f) {
            continue;
        }
        // If the first colour is saturated, then avoid unsaturated second colours
        if (hsvA.s > 0.5f && hsvC.s < 0.1f) {
            continue;
        }
        // If the first colour is unsaturated, then avoid unsaturated second colours
        if (hsvA.s < 0.1f && hsvC.s < 0.5f) {
            continue;
        }
        // Avoid unsaturated colours that aren't used much
        if (i >= 4 && hsvC.s < 0.1f) {
            continue;
        }
        // Avoid low value colours that aren't used much
        if (i >= 6 && hsvC.v > 0.3f) {
            continue;
        }
        // The hue difference is that of the angles
        auto diff = angleDiff(hsvA.h, hsvC.h);
        if (diff > maxDiff) {
            maxIndex = i;
            maxDiff = diff;
        }
    }
    colourB = bestBuckets[maxIndex].colour;
}

Pixel[] createMinimalIcon(size_t id, string name, Font font, Pixel colourA, Pixel colourB, int iconSize, int margin) {
    Pixel[] icon;
    icon.length = iconSize ^^ 2;

    auto random = Random(cast(int) (id * 9438983));

    auto drawSize = iconSize - margin * 2;
    auto minRectSize = cast(int) (drawSize * 0.35);
    auto aWidth = uniform(minRectSize, drawSize / 2, random);
    auto aHeight = uniform(minRectSize, drawSize, random);
    auto bWidth = uniform(minRectSize, drawSize / 2, random);
    auto bHeight = uniform(minRectSize, drawSize, random);

    alias ModCoord = int delegate(int c);
    ModCoord intIdentity = (int c) => c;
    ModCoord flipCord = (int c) => iconSize - 1 - c;

    ModCoord axMod = void;
    ModCoord ayMod = void;
    ModCoord byMod = void;
    if (uniform!ubyte(random) > 127) {
        ayMod = intIdentity;
        byMod = flipCord;
    } else {
        ayMod = flipCord;
        byMod = intIdentity;
    }

    foreach (yy; 0 .. aHeight) {
        auto y = ayMod(yy + margin);
        foreach (xx; 0 .. aWidth) {
            auto x = intIdentity(xx + margin);
            icon[x + y * iconSize] = colourA;
        }
    }

    foreach (yy; 0 .. bHeight) {
        auto y = byMod(yy + margin);
        foreach (xx; 0 .. bWidth) {
            auto x = flipCord(xx + margin);
            icon[x + y * iconSize] = colourB;
        }
    }

    enum maxLineLength = 6;
    auto twoLines = name.length > maxLineLength;
    auto firstLine = name[0 .. twoLines ? ($ + 1) / 2 : $];
    auto lineHeight = font.textSize(firstLine.to!dstring()).y;
    firstLine.drawText(font, icon, iconSize, iconSize / 2, iconSize / 2 - (twoLines ? lineHeight / 2 : 0));
    if (twoLines) {
        auto secondLine = name[$ - $ / 2 .. $];
        secondLine.drawText(font, icon, iconSize, iconSize / 2, iconSize / 2 + lineHeight / 2);
    }

    return icon;
}

void drawText(string text, Font font, Pixel[] icon, int size, int x, int y) {
    // Draw the text to a buffer
    auto dtext = text.to!dstring();
    auto textSize = font.textSize(dtext);
    auto buffer = new ColorDrawBuf(textSize.x, textSize.y);
    buffer.fill(0xFFFFFF);
    font.drawText(buffer, 0, 0, dtext, 0x0);
    buffer.invertAlpha();
    // Copy the buffer to the icon
    foreach (yy; 0 .. textSize.y) {
        auto py = y + yy - textSize.y / 2;
        auto scanLine = buffer.scanLine(yy);
        foreach (xx; 0 .. textSize.x) {
            auto px = x + xx - textSize.x / 2;
            auto textArgb = scanLine[xx];
            auto pixelAddress = icon.ptr + (px + py * size);
            *pixelAddress = Pixel(textArgb >>> 16, textArgb >>> 8, textArgb, textArgb >>> 24);
        }
    }
}

string[size_t] loadPokemonNames(string pokedexFile = "pokedex.csv") {
    string[size_t] nameById;
    foreach (record; csvReader!(string[string])(pokedexFile.readText(), null)) {
        auto natId = record["Nat"];
        if (natId.canFind(".")) {
            continue;
        }
        auto mainId = natId.to!size_t();
        auto mainName = record["Pokemon"].findSplitBefore(" (")[0];
        nameById[mainId] = mainName;
    }
    return nameById;
}

void loadIcon(string spriteFile, ref IconPixels destination) {
    FIBITMAP *bitmap = FreeImage_Load(FIF_PNG, spriteFile.toStringz());
    assert (bitmap);

    auto width = FreeImage_GetWidth(bitmap);
    auto height = FreeImage_GetHeight(bitmap);
    assert (width >= ICON_SIZE);
    assert (height >= ICON_SIZE);

    auto pixelSize = FreeImage_GetLine(bitmap) / width;
    foreach (y; 0 .. ICON_SIZE) {
        auto line = FreeImage_GetScanLine(bitmap, y);
        foreach (x; 0 .. ICON_SIZE) {
            destination[x + (ICON_SIZE - 1 - y) * ICON_SIZE] =
                    Pixel(line[FI_RGBA_RED], line[FI_RGBA_GREEN], line[FI_RGBA_BLUE]);
            line += pixelSize;
        }
    }

    FreeImage_Unload(bitmap);
}

string saveIcon(size_t id, ref IconPixels icon, string outputDir) {
    return saveIcon(id, icon[], ICON_SIZE, outputDir);
}

string saveIcon(size_t id, Pixel[] icon, int size, string outputDir) {
    auto bitmap = FreeImage_Allocate(size, size, 32,
            FI_RGBA_RED_MASK, FI_RGBA_GREEN_MASK, FI_RGBA_BLUE_MASK);

    auto pixelSize = FreeImage_GetLine(bitmap) / size;

    foreach (y; 0 .. size) {
        auto line = FreeImage_GetScanLine(bitmap, y);

        foreach (x; 0 .. size) {
            auto pixel = icon[x + (size - 1 - y) * size];
            line[FI_RGBA_RED] = pixel.toUbyte!"r";
            line[FI_RGBA_GREEN] = pixel.toUbyte!"g";
            line[FI_RGBA_BLUE] = pixel.toUbyte!"b";
            line[FI_RGBA_ALPHA] = pixel.toUbyte!"a";
            line += pixelSize;
        }
    }

    auto outputFile = outputDir.buildPath(format("%d.png", id));
    assert (FreeImage_Save(FIF_PNG, bitmap, outputFile.toStringz()));

    FreeImage_Unload(bitmap);

    return outputFile;
}

string createJson(string[size_t] idToFile) {
    JSONValue json;
    foreach (id, file; idToFile) {
        auto idString = format("id%s", id);
        auto url = format(GH_REPO_RAW_FORMAT, file);
        json[idString] = ["url" : url];
    }
    return json.toPrettyString();
}

Pixel rgb2hsv(Pixel rgb) {
    auto min = rgb.r < rgb.g ? rgb.r : rgb.g;
    min = min  < rgb.b ? min : rgb.b;
    auto max = rgb.r > rgb.g ? rgb.r : rgb.g;
    max = max  > rgb.b ? max : rgb.b;

    Pixel hsv;
    hsv.a = 1;
    hsv.v = max;
    auto delta = max - min;
    if (delta < 0.00001f) {
        hsv.s = 0;
        hsv.h = 0;
        return hsv;
    } if (max > 0) {
        hsv.s = (delta / max);
    } else {
        hsv.s = 0;
        hsv.h = float.nan;
        return hsv;
    }
    if (rgb.r >= max) {
        hsv.h = (rgb.g - rgb.b) / delta;
    } else if (rgb.g >= max) {
        hsv.h = 2 + ( rgb.b - rgb.r) / delta;
    } else {
        hsv.h = 4 + ( rgb.r - rgb.g) / delta;
    }
    hsv.h *= 60;

    if (hsv.h < 0) {
        hsv.h += 360;
    }

    return hsv;
}

float angleDiff(float a, float b) {
    a = a.degToRag();
    b = b.degToRag();
	return abs(acos(cos(a) * cos(b) + sin(a) * sin(b)));
}

float degToRag(float deg) {
    return deg * (PI / 180);
}
