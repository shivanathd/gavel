/**
 * A PNG or JPEG sent with a judgment (Jev 1.14 and later). State carries only its reference, "<image:"
 * plus the first 32 hex digits of the SHA-256 of the bytes, so the state hash covers the image itself.
 * Built by state sources such as Gavel_StateSources.RecordImage; never stored in the ledger.
 */
public with sharing class Gavel_ImageAsset {
    public static final Integer MAX_BYTES = 3 * 1024 * 1024;
    /** Heap needed to send an image, in multiples of its size (bytes, hex text, multipart body). */
    public static final Integer HEAP_FACTOR = 6;

    @TestVisible
    private static Integer testMaxBytes;

    public Blob data;
    public String contentType;
    public String reference;

    public Gavel_ImageAsset(Blob data, String contentType) {
        this.data = data;
        this.contentType = contentType;
        this.reference = '<image:' + EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', data)).left(32) + '>';
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
