/**
 * A PNG or JPEG sent with a judgment (Jev 1.14 and later). State carries only its reference, "<image:"
 * plus the first 32 hex digits of the SHA-256 of the bytes, so the state hash covers the image itself.
 * Built by state sources such as Gavel_StateSources.RecordImage; never stored in the ledger.
 */
public with sharing class Gavel_ImageAsset {
    public static final Integer MAX_BYTES = 3 * 1024 * 1024;
    /** Heap needed to send an image, in multiples of its size (bytes, hex text, multipart body). */
    public static final Integer HEAP_FACTOR = 6;
    /** Side lengths TypeSafe accepts, in pixels (measured against api.typesafe.ai on 2026-10-17). */
    public static final Integer MIN_SIDE = 280;
    public static final Integer MAX_SIDE = 1568;

    @TestVisible
    private static Integer testMaxBytes;

    public Blob data;
    public String contentType;
    public String reference;
    private List<Integer> size;

    public Gavel_ImageAsset(Blob data, String contentType) {
        this.data = data;
        this.contentType = contentType;
        this.reference = '<image:' + EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', data)).left(32) + '>';
    }

    /** True when both sides are within MIN_SIDE..MAX_SIDE. Unreadable headers count as unsupported. */
    public Boolean hasSupportedSize() {
        List<Integer> wh = dimensions();
        return wh != null && Math.min(wh[0], wh[1]) >= MIN_SIDE && Math.max(wh[0], wh[1]) <= MAX_SIDE;
    }

    /** [width, height] in pixels from the PNG IHDR chunk or the JPEG SOFn marker, or null when unreadable. */
    public List<Integer> dimensions() {
        if (size == null && data != null) {
            size = readSize(EncodingUtil.convertToHex(data));
        }
        return size;
    }

    private static List<Integer> readSize(String hex) {
        if (hex.startsWith('89504e470d0a1a0a') && hex.length() >= 66 && hex.substring(24, 32) == '49484452') { // IHDR, 13-byte body
            return new List<Integer>{ toInt(hex.substring(32, 40)), toInt(hex.substring(40, 48)) };
        }
        if (!hex.startsWith('ffd8')) {
            return null;
        }
        Integer i = 4;
        while (i + 18 <= hex.length()) {
            if (hex.substring(i, i + 2) != 'ff') {
                return null;
            }
            String marker = hex.substring(i + 2, i + 4);
            if (marker == 'ff') {
                i += 2; // fill byte
                continue;
            }
            if (marker == '01' || (marker >= 'd0' && marker <= 'd8')) {
                i += 4; // markers without a length
                continue;
            }
            // SOF0..SOF15 except DHT (c4), JPG (c8) and DAC (cc): length, precision, height, width
            if (marker >= 'c0' && marker <= 'cf' && marker != 'c4' && marker != 'c8' && marker != 'cc') {
                return new List<Integer>{ toInt(hex.substring(i + 14, i + 18)), toInt(hex.substring(i + 10, i + 14)) };
            }
            i += 4 + toInt(hex.substring(i + 4, i + 8)) * 2;
        }
        return null;
    }

    private static Integer toInt(String hex) {
        Integer n = 0;
        for (Integer k = 0; k < hex.length(); k++) {
            n = n * 16 + '0123456789abcdef'.indexOf(hex.substring(k, k + 1));
        }
        return n;
    }

    /** Largest image this transaction can still send without hitting the heap limit (async runs allow more). */
    public static Integer maxBytes() {
        if (testMaxBytes != null) {
            return testMaxBytes;
        }
        Integer free = Math.max(0, Limits.getLimitHeapSize() - Limits.getHeapSize());
        return Math.min(MAX_BYTES, free / (HEAP_FACTOR + 1));
    }
}
