/**
 * Minimal structured logger (JSON lines to the debug log).
 */
public with sharing class Logger {
    @TestVisible
    private static final List<String> BUFFER = new List<String>();

    public static void info(String source, String message) {
        write(LoggingLevel.INFO, source, message);
    }

    public static void error(String source, String message) {
        write(LoggingLevel.ERROR, source, message);
    }

    public static Integer logSaveErrors(String source, List<Database.SaveResult> results) {
        Integer failures = 0;
        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
                failures++;
                for (Database.Error err : result.getErrors()) {
                    error(source, result.getId() + ' ' + err.getStatusCode() + ': ' + err.getMessage());
                }
            }
        }
        return failures;
    }

    private static void write(LoggingLevel level, String source, String message) {
        String line = JSON.serialize(
            new Map<String, Object>{ 'level' => level.name(), 'source' => source, 'message' => message }
        );
        BUFFER.add(line);
        System.debug(level, line);
    }
}
