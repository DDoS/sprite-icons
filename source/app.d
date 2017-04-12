import std.path : buildPath;
import std.file : dirEntries, exists, isDir, mkdirRecurse, write, DirEntry, SpanMode;
import std.regex : regex, matchAll;
import std.string : toStringz, format;
import std.conv : to;
import std.json : toJSON, JSONValue;

import derelict.freeimage.freeimage;

enum ICON_SIZE = 64;

enum REPO_USER = "DDoS";
enum REPO_NAME = "sprite-icons";
enum GH_REPO_RAW_FORMAT = "https://raw.githubusercontent.com/" ~ REPO_USER ~ "/"
        ~ REPO_NAME ~ "/master/%s";

struct Pixel {
    ubyte r;
    ubyte g;
    ubyte b;
    ubyte a;
}

alias IconPixels = Pixel[ICON_SIZE * ICON_SIZE];

void main(string[] args) {
    assert(args.length == 3);

    DerelictFI.load();

    auto sourceDir = args[1];
    auto outputDir = args[2];

    assert (sourceDir.exists() && sourceDir.isDir());
    if (!outputDir.exists()) {
        outputDir.mkdirRecurse();
    }

    string[size_t] idToFile;
    sourceDir.buildPath("GenI").convertGen(outputDir, idToFile);
    sourceDir.buildPath("GenII").convertGen(outputDir, idToFile);
    //sourceDir.buildPath("GenIII").convertGen(outputDir, idToFile);

    auto json = createJson(idToFile);
    outputDir.buildPath("icons.json").write(json);
}

void convertGen(string sourceDir, string outputDir, ref string[size_t] idToFile) {
    auto threeNumImage = regex(r"(\d\d\d)\.png");

    foreach (DirEntry file; dirEntries(sourceDir, SpanMode.shallow)) {
        if (!file.isFile) {
            continue;
        }

        auto numberText = file.name.matchAll(threeNumImage);
        if (numberText.empty()) {
            continue;
        }
        auto number = to!size_t(numberText.front[1]);
        numberText.popFront();
        assert (numberText.empty);

        IconPixels icon;
        loadIcon(file, icon);
        makeTransparent(icon);
        idToFile[number] = saveIcon(number, icon, outputDir);
    }
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
            auto pixel = destination.ptr + (x + (ICON_SIZE - 1 - y) * ICON_SIZE);
            pixel.r = line[FI_RGBA_RED];
            pixel.g = line[FI_RGBA_GREEN];
            pixel.b = line[FI_RGBA_BLUE];
            pixel.a = BYTE.max;
            line += pixelSize;
        }
    }

    FreeImage_Unload(bitmap);
}

void makeTransparent(ref IconPixels icon) {
    // We'll asume that the bottom right corner is always a background pixel
    auto transparent = icon[0];
    foreach(i; 0 .. ICON_SIZE * ICON_SIZE) {
        if (icon[i] == transparent) {
            icon[i].a = BYTE.min;
        }
    }
}

string saveIcon(size_t id, ref IconPixels icon, string outputDir) {
    auto bitmap = FreeImage_Allocate(ICON_SIZE, ICON_SIZE, 32,
            FI_RGBA_RED_MASK, FI_RGBA_GREEN_MASK, FI_RGBA_BLUE_MASK);

    auto pixelSize = FreeImage_GetLine(bitmap) / ICON_SIZE;

    foreach (y; 0 .. ICON_SIZE) {
        auto line = FreeImage_GetScanLine(bitmap, y);

        foreach (x; 0 .. ICON_SIZE) {
            auto pixel = icon.ptr + (x + (ICON_SIZE - 1 - y) * ICON_SIZE);
            line[FI_RGBA_RED] = pixel.r;
            line[FI_RGBA_GREEN] = pixel.g;
            line[FI_RGBA_BLUE] = pixel.b;
            line[FI_RGBA_ALPHA] = pixel.a;
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
        json[idString] = url;
    }
    return toJSON(json, true);
}
