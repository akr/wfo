AC_INIT(wvs, 0.1)

AC_ARG_WITH(ruby,
  AS_HELP_STRING([--with-ruby=pathname], [specify ruby binary pathname]),
  [AC_SUBST([RUBY], [$withval])],
  [AC_PATH_PROG([RUBY], [ruby])])

AC_CONFIG_FILES([Makefile])
AC_OUTPUT

