/**
 * Small key/value store over the Platform Cache org partition "Gavel", with an in-memory implementation for
 * tests. A missing or zero-capacity partition makes every call a miss (OPS-001.5); callers fall back to
 * Gavel_Counter__c.
 */
public with sharing class Gavel_CacheStore {
    public interface Store {
        Object get(String key);
        void put(String key, Object value, Integer ttlSeconds);
        Boolean available();
    }

    public class PlatformStore implements Store {
        private Cache.OrgPartition partition;
        private Boolean ok;

        private Cache.OrgPartition part() {
            if (ok == null) {
                try {
                    partition = Cache.Org.getPartition('local.Gavel');
                    ok = partition != null;
                } catch (Exception e) {
                    ok = false;
                }
            }
            return ok ? partition : null;
        }

        public Boolean available() {
            return part() != null;
        }

        public Object get(String key) {
            try {
                Cache.OrgPartition p = part();
                return p == null ? null : p.get(key);
            } catch (Exception e) {
                return null;
            }
        }

        public void put(String key, Object value, Integer ttlSeconds) {
            try {
                Cache.OrgPartition p = part();
                if (p != null) {
                    p.put(key, value, Math.max(300, Math.min(ttlSeconds, 172800)));
                }
            } catch (Exception e) {
                ok = false;
            }
        }
    }

    public class MemoryStore implements Store {
        public Map<String, Object> data = new Map<String, Object>();
        public Boolean enabled = true;

        public Boolean available() {
            return enabled;
        }

        public Object get(String key) {
            return enabled ? data.get(key) : null;
        }

        public void put(String key, Object value, Integer ttlSeconds) {
            if (enabled) {
                data.put(key, value);
            }
        }
    }

    /** Keys must be alphanumeric for Platform Cache (PROGRESS.md B4). */
    public static String key(String prefix, String raw) {
        return (prefix + raw).replaceAll('[^A-Za-z0-9]', '').left(250);
    }
}
