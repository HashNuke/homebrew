require 'formula'

# Reference: https://github.com/b4winckler/macvim/wiki/building
class Macvim < Formula
  homepage 'http://code.google.com/p/macvim/'
  url 'https://github.com/b4winckler/macvim/archive/snapshot-72.tar.gz'
  version '7.4-72'
  sha1 '3fb5b09d7496c8031a40e7a73374424ef6c81166'

  head 'https://github.com/b4winckler/macvim.git', :branch => 'master'

  option "custom-icons", "Try to generate custom document icons"
  option "override-system-vim", "Override system vim"

  depends_on :xcode
  depends_on 'cscope' => :recommended
  depends_on 'lua' => :optional
  depends_on 'luajit' => :optional
  depends_on :python => :recommended
  depends_on :python3 => :optional

  env :std if MacOS.version <= :snow_leopard
  # Help us! We'd like to use superenv in these environments too

  def install
    # MacVim doesn't have and required any Python package, unset PYTHONPATH.
    ENV.delete('PYTHONPATH')

    # Set ARCHFLAGS so the Python app (with C extension) that is
    # used to create the custom icons will not try to compile in
    # PPC support (which isn't needed in Homebrew-supported systems.)
    ENV['ARCHFLAGS'] = "-arch #{MacOS.preferred_arch}"

    # If building for 10.7 or up, make sure that CC is set to "clang".
    ENV.clang if MacOS.version >= :lion

    # macvim HEAD only works with the current Ruby.framework because it builds with -framework Ruby
    system_ruby = "/System/Library/Frameworks/Ruby.framework/Versions/Current/usr/bin/ruby"

    args = %W[
      --with-features=huge
      --enable-multibyte
      --with-macarchs=#{MacOS.preferred_arch}
      --enable-perlinterp
      --enable-rubyinterp
      --enable-tclinterp
      --with-ruby-command=#{system_ruby}
      --with-tlib=ncurses
      --with-compiledby=Homebrew
      --with-local-dir=#{HOMEBREW_PREFIX}
    ]

    args << "--with-macsdk=#{MacOS.version}" unless MacOS::CLT.installed?
    args << "--enable-cscope" if build.with? "cscope"

    if build.with? "lua"
      args << "--enable-luainterp"
      args << "--with-lua-prefix=#{HOMEBREW_PREFIX}"
    end

    if build.with? "luajit"
      args << "--enable-luainterp"
      args << "--with-lua-prefix=#{HOMEBREW_PREFIX}"
      args << "--with-luajit"
    end

    if build.with? "python" and build.with? "python3"
      args << "--enable-pythoninterp=dynamic" << "--enable-python3interp=dynamic"
    else
      args << "--enable-pythoninterp" if build.with? "python"
      args << "--enable-python3interp" if build.with? "python3"
    end

    # MacVim seems to link Python by `-framework Python` (instead of
    # `python-config --ldflags`) and so we have to pass the -F to point to
    # where the Python.framework is located, we want it to use!
    # Also the -L is needed for the correct linking. This is a mess but we have
    # to wait until MacVim is really able to link against different Python's
    # on the Mac. Note configure detects brewed python correctly, but that
    # is ignored.
    # See https://github.com/mxcl/homebrew/issues/17908
    if python2 and python2.framework? and not build.with? "python3"
      ENV.prepend 'LDFLAGS', "-L#{python2.libdir} -F#{python2.framework}"
    end

    unless MacOS::CLT.installed?
      # On Xcode-only systems:
      # Macvim cannot deal with "/Applications/Xcode.app/Contents/Developer" as
      # it is returned by `xcode-select -print-path` and already set by
      # Homebrew (in superenv). Instead Macvim needs the deeper dir to directly
      # append "SDKs/...".
      args << "--with-developer-dir=#{MacOS::Xcode.prefix}/Platforms/MacOSX.platform/Developer/"
    end

    system "./configure", *args

    if build.with? "python" and build.with? "python3"
      # On 64-bit systems, we need to avoid a 32-bit Framework Python.
      # MacVim doesn't check Python while compiling.
      python do
        if MacOS.prefer_64_bit? and python.framework? and not archs_for_command("#{python.prefix}/Python").include? :x86_64
          opoo "Detected a framework Python that does not have 64-bit support in:"
          puts <<-EOS.undent
            #{python.prefix}

            Dynamic loading Python library required the same architecture.

            Note that a framework Python in /Library/Frameworks/Python.framework is
            the "MacPython" version, and not the system-provided version which is in:
              /System/Library/Frameworks/Python.framework
          EOS
        end
      end
      # Help vim find Python's library as absolute path.
      python do
        inreplace 'src/auto/config.mk', /-DDYNAMIC_PYTHON#{python.if3then3}_DLL=\\".*\\"/, %Q[-DDYNAMIC_PYTHON#{python.if3then3}_DLL=\'\"#{python.prefix}/Python\"\'] if python.framework?
      end
      # Force vim loading different Python on same time, may cause vim crash.
      unless python.brewed?
        opoo "Your python isn't comes from Homebrew, you may see warning massage during brewing. That's OK. Because we can't detect what your Python is. We will force replace the string."
        inreplace 'src/auto/config.h', "/* #undef PY_NO_RTLD_GLOBAL */", "#define PY_NO_RTLD_GLOBAL 1"
        inreplace 'src/auto/config.h', "/* #undef PY3_NO_RTLD_GLOBAL */", "#define PY3_NO_RTLD_GLOBAL 1"
      end
    end

    if build.include? "custom-icons"
      # Get the custom font used by the icons
      cd 'src/MacVim/icons' do
        system "make getenvy"
      end
    else
      # Building custom icons fails for many users, so off by default.
      inreplace "src/MacVim/icons/Makefile", "$(MAKE) -C makeicns", ""
      inreplace "src/MacVim/icons/make_icons.py", "dont_create = False", "dont_create = True"
    end

    system "make"

    prefix.install "src/MacVim/build/Release/MacVim.app"
    inreplace "src/MacVim/mvim", /^# VIM_APP_DIR=\/Applications$/,
                                 "VIM_APP_DIR=#{prefix}"
    bin.install "src/MacVim/mvim"

    # Create MacVim vimdiff, view, ex equivalents
    executables = %w[mvimdiff mview mvimex gvim gvimdiff gview gvimex]
    executables += %w[vi vim vimdiff view vimex] if build.include? "override-system-vim"
    executables.each {|f| ln_s bin+'mvim', bin+f}
  end

  def caveats
    s = ''
    s += <<-EOS.undent
      MacVim.app installed to:
        #{prefix}

      To link the application to a normal Mac OS X location:
          brew linkapps
      or:
          brew linkapps --local
    EOS
    if build.with? "python" and build.with? "python3"
      s += <<-EOS.undent

        This MacVim build with dynamic library Python 2 & 3.

        Note that MacVim load dynamic Python 2 & 3 library with the same time
        may crash MacVim. For more information, see:
            http://vimdoc.sourceforge.net/htmldoc/if_pyth.html#python3
      EOS
    end
    return s
  end
end
