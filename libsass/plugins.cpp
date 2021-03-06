#ifdef _WIN32
#include <windows.h>
#else
#include <sys/types.h>
#include <dirent.h>
#include <errno.h>
#include <dlfcn.h>
#endif

#include <iostream>
#include "output.hpp"
#include "plugins.hpp"

#define npos string::npos

namespace Sass {

  Plugins::Plugins(void) { }
  Plugins::~Plugins(void) { }

  // check if plugin is compatible with this version
  // plugins may be linked static against libsass
  // we try to be compatible between major versions
  inline bool compatibility(const char* their_version)
  {
// const char* their_version = "3.1.2";
    // first check if anyone has an unknown version
    const char* our_version = libsass_version();
    if (!strcmp(their_version, "[na]")) return false;
    if (!strcmp(our_version, "[na]")) return false;

    // find the position of the second dot
    size_t pos = string(our_version).find('.', 0);
    if (pos != npos) pos = string(our_version).find('.', pos + 1);

    // if we do not have two dots we fallback to compare complete string
    if (pos == npos) { return strcmp(their_version, our_version) ? 0 : 1; }
    // otherwise only compare up to the second dot (major versions)
    else { return strncmp(their_version, our_version, pos) ? 0 : 1; }

  }

  // load one specific plugin
  bool Plugins::load_plugin (const string& path)
  {

    typedef const char* (*__plugin_version__)(void);
    typedef Sass_Function_List (*__plugin_load_fns__)(void);
    typedef Sass_Importer_List (*__plugin_load_imps__)(void);

    if (LOAD_LIB(plugin, path))
    {
      // try to load initial function to query libsass version suppor
      if (LOAD_LIB_FN(__plugin_version__, plugin_version, "libsass_get_version"))
      {
        // get the libsass version of the plugin
        if (!compatibility(plugin_version())) return false;
        // try to get import address for "libsass_load_functions"
        if (LOAD_LIB_FN(__plugin_load_fns__, plugin_load_functions, "libsass_load_functions"))
        {
          Sass_Function_List fns = plugin_load_functions();
          while (fns && *fns) { functions.push_back(*fns); ++ fns; }
        }
        // try to get import address for "libsass_load_importers"
        if (LOAD_LIB_FN(__plugin_load_imps__, plugin_load_importers, "libsass_load_importers"))
        {
          Sass_Importer_List imps = plugin_load_importers();
          while (imps && *imps) { importers.push_back(*imps); ++ imps; }
        }
        // try to get import address for "libsass_load_headers"
        if (LOAD_LIB_FN(__plugin_load_imps__, plugin_load_headers, "libsass_load_headers"))
        {
          Sass_Importer_List imps = plugin_load_headers();
          while (imps && *imps) { headers.push_back(*imps); ++ imps; }
        }
        // success
        return true;
      }
      else
      {
        // print debug message to stderr (should not happen)
        cerr << "failed loading 'libsass_support' in <" << path << ">" << endl;
        if (const char* dlsym_error = dlerror()) cerr << dlsym_error << endl;
        CLOSE_LIB(plugin);
      }
    }
    else
    {
      // print debug message to stderr (should not happen)
      cerr << "failed loading plugin <" << path << ">" << endl;
      if (const char* dlopen_error = dlerror()) cerr << dlopen_error << endl;
    }

    return false;

  }

  size_t Plugins::load_plugins(const string& path)
  {

    // count plugins
    size_t loaded = 0;

    #ifdef _WIN32

      try
      {

        // use wchar (utf16)
        WIN32_FIND_DATAW data;
        // trailing slash is guaranteed
        string globsrch(path + "*.dll");
        // convert to wide chars (utf16) for system call
        wstring wglobsrch(UTF_8::convert_to_utf16(globsrch));
        HANDLE hFile = FindFirstFileW(wglobsrch.c_str(), &data);
        // check if system called returned a result
        // ToDo: maybe we should print a debug message
        if (hFile == INVALID_HANDLE_VALUE) return -1;

        // read directory
        while (true)
        {
          try
          {
            // the system will report the filenames with wide chars (utf16)
            string entry = UTF_8::convert_from_utf16(data.cFileName);
            // check if file ending matches exactly
            if (!ends_with(entry, ".dll")) continue;
            // load the plugin and increase counter
            if (load_plugin(path + entry)) ++ loaded;
            // check if there should be more entries
            if (GetLastError() == ERROR_NO_MORE_FILES) break;
            // load next entry (check for return type)
            if (!FindNextFileW(hFile, &data)) break;
          }
          catch (...)
          {
            // report the error to the console (should not happen)
            // seems like we got strange data from the system call?
            cerr << "filename in plugin path has invalid utf8?" << endl;
          }
        }
      }
      catch (utf8::invalid_utf8)
      {
        // report the error to the console (should not happen)
        // implementors should make sure to provide valid utf8
        cerr << "plugin path contains invalid utf8" << endl;
      }

    #else

      DIR *dp;
      struct dirent *dirp;
      if((dp  = opendir(path.c_str())) == NULL) return -1;
      while ((dirp = readdir(dp)) != NULL) {
        if (!ends_with(dirp->d_name, ".so")) continue;
        if (load_plugin(path + dirp->d_name)) ++ loaded;
      }
      closedir(dp);

    #endif
    return loaded;

  }

}

