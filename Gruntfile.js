/**
 * Project: wiola
 * User: KSDaemon
 * Date: 14.04.14
 */

module.exports = function (grunt) {

    require('load-grunt-tasks')(grunt);

    // Project configuration.
    grunt.initConfig({
        pkg  : grunt.file.readJSON('package.json'),
        clean: {
            dist: ['lib/*']
        },
        copy : {
            main: {
                expand : true,
                flatten: true,
                src    : 'src/wiola/wiola.lua',
                dest   : 'lib/',
                options: {
                    process: function (content, srcpath) {
                        return content.replace(/\s*(\-\-)?\s*ngx\.log.*/g, '')
                            .replace(/.*getdump.*/g, '')
                            .replace(/.*numericbin.*/g, '');
                    }
                }
            },
            lib : {
                expand : true,
                cwd    : 'src/wiola/',
                src    : '**/*.lua',
                dest   : 'lib/wiola/',
                options: {
                    process: function (content, srcpath) {
                        return content.replace(/\s*(\-\-)?\s*ngx\.log.*/g, '')
                            .replace(/.*getdump.*/g, '')
                            .replace(/.*numericbin.*/g, '');
                    }
                }
            }
        }
    });

    grunt.registerTask('default', ['clean', 'copy']);
};
