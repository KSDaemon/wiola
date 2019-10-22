/**
 * Project: wiola
 * User: KSDaemon
 * Date: 14.04.14
 */

module.exports = function(grunt) {

    require('load-grunt-tasks')(grunt);

    // Project configuration.
    grunt.initConfig({
        pkg: grunt.file.readJSON('package.json'),
        clean: {
            dist: ['lib/*']
        },
        copy: {
            main: {
                files: [
                    {
                        expand: true,
                        flatten: true,
                        src: 'src/wiola/wiola.lua',
                        dest: 'lib/',
                        options: {
                            process: function (content, srcpath) {
                                return content.replace(/\s*(\-\-)?\s*ngx\.log.*/g,'')
                                    .replace(/.*getdump.*/g,'');
                            }
                        }
                    },
                    {
                        expand: true,
                        cwd: 'src/wiola/',
                        src: '**/*.lua',
                        dest: 'lib/wiola/',
                        options: {
                            process: function (content, srcpath) {
                                return content.replace(/\s*(\-\-)?\s*ngx\.log.*/g,'')
                                    .replace(/.*getdump.*/g,'');
                            }
                        }
                    }
                ]
            }
        }
    });

    grunt.registerTask('default', ['clean', 'copy']);
};
