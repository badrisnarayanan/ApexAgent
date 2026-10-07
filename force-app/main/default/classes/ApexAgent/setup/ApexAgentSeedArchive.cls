/**
 * Read access to the starter configuration that ships in the ApexAgentSeedData
 * static resource: a zip holding data.json (the records and how they link) and
 * one text file per instruction.
 *
 * Instructions live in their own files rather than inside data.json so each
 * one stays readable and diffable in source control. The resource is produced
 * by seed/export-seed.js.
 */
public with sharing class ApexAgentSeedArchive {

    public static final String RESOURCE_NAME = 'ApexAgentSeedData';
    @TestVisible private static final String DATA_ENTRY = 'data.json';

    public class SeedArchiveException extends Exception {}

    private final Compression.ZipReader reader;
    private final Set<String> entryNames;

    public ApexAgentSeedArchive(Blob zipArchive) {
        try {
            this.reader = new Compression.ZipReader(zipArchive);
            this.entryNames = new Set<String>(this.reader.getEntryNames());
        } catch (Exception e) {
            throw new SeedArchiveException('The seed data is not a readable zip archive: ' + e.getMessage(), e);
        }
    }

    // Static resources are setup metadata with no CRUD or FLS to enforce.
    @SuppressWarnings('PMD.ApexCRUDViolation')
    public static ApexAgentSeedArchive fromStaticResource() {
        List<StaticResource> resources = [SELECT Body FROM StaticResource WHERE Name = :RESOURCE_NAME LIMIT 1];
        if (resources.isEmpty()) {
            throw new SeedArchiveException(
                'Static resource ' + RESOURCE_NAME + ' was not found. Deploy the project before running setup.'
            );
        }
        return new ApexAgentSeedArchive(resources[0].Body);
    }

    /** @return the parsed contents of data.json. */
    public Map<String, Object> readData() {
        String json = readText(DATA_ENTRY);
        try {
            return (Map<String, Object>) System.JSON.deserializeUntyped(json);
        } catch (Exception e) {
            throw new SeedArchiveException(DATA_ENTRY + ' in the seed data is not a valid JSON object: ' + e.getMessage(), e);
        }
    }

    /** @return the full text of one file in the archive, by its path inside the zip. */
    public String readText(String entryName) {
        if (String.isBlank(entryName) || !entryNames.contains(entryName)) {
            throw new SeedArchiveException('The seed data has no file named "' + entryName + '".');
        }
        return reader.extract(entryName).toString();
    }
}
