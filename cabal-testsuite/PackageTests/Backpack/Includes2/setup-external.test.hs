import Test.Cabal.Prelude
main = setupAndCabalTest $ do
  skipUnlessGhcVersion ">= 8.1"
  ghc <- isGhcVersion "== 9.0.2 || == 9.2.* || == 9.4.*"
  expectBrokenIf ghc 7987 $ do
    withPackageDb $ do
      withDirectory "mylib" $ setup_install_with_docs ["--ipid", "mylib-0.1.0.0"]
      withDirectory "mysql" $ setup_install_with_docs ["--ipid", "mysql-0.1.0.0"]
      withDirectory "postgresql" $ setup_install_with_docs ["--ipid", "postgresql-0.1.0.0"]
      withDirectory "mylib" $
        setup_install_with_docs ["--ipid", "mylib-0.1.0.0",
                       "--instantiate-with", "Database=mysql-0.1.0.0:Database.MySQL"]
      withDirectory "mylib" $
        setup_install_with_docs ["--ipid", "mylib-0.1.0.0",
                       "--instantiate-with", "Database=postgresql-0.1.0.0:Database.PostgreSQL"]
      withDirectory "src" $ setup_install_with_docs []
      withDirectory "exe" $ do
        setup_install_with_docs []
        runExe' "exe" [] >>= assertOutputContains "minemysql minepostgresql"
