/**
 * Project: wiola
 * User: KSDaemon
 * Date: 14.04.14
 */

module.exports = function(grunt) {
    // Project configuration.
    grunt.initConfig({
        pkg: grunt.file.readJSON('package.json'),
        copy: {
            main: {
                expand: true,
                flatten: true,
                src: 'src/wiola/*.lua',
                dest: 'lib/',
                options: {
                    process: function (content, srcpath) {
                        return content.replace(/\s*(\-\-)?\s*ngx\.log.*/g,'')
                            .replace(/\s*require.*debug\.var_dump.*/g,'')
                            .replace(/\s*(\-\-)?\s*var_dump.*/g,'');
                    }
                }
            }
        }
    });

    grunt.loadNpmTasks('grunt-contrib-copy');

    grunt.registerTask('default', ['copy']);
};
