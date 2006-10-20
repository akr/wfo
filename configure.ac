AC_INIT(wfo, 0.1)

AC_ARG_WITH(ruby,
  AS_HELP_STRING([--with-ruby=PATHNAME], [use ruby interpreter specified by PATHNAME]),
  [AC_SUBST([RUBY], [$withval])],
  [AC_PATH_PROG([RUBY], [ruby])])

AC_CONFIG_FILES([Makefile])
AC_OUTPUT

