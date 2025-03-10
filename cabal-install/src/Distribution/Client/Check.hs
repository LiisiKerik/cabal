{-# LANGUAGE CPP #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Distribution.Client.Check
-- Copyright   :  (c) Lennart Kolmodin 2008
-- License     :  BSD-like
--
-- Maintainer  :  kolmodin@haskell.org
-- Stability   :  provisional
-- Portability :  portable
--
-- Check a package for common mistakes
--
-----------------------------------------------------------------------------
module Distribution.Client.Check (
    check
  ) where


import Distribution.Client.Compat.Prelude
import Prelude ()

import Distribution.Client.Utils.Parsec              (renderParseError)
import Distribution.PackageDescription               (GenericPackageDescription)
import Distribution.PackageDescription.Check
import Distribution.PackageDescription.Configuration (flattenPackageDescription)
import Distribution.PackageDescription.Parsec
       (parseGenericPackageDescription, runParseResult)
import Distribution.Parsec                           (PWarning (..), showPError)
import Distribution.Simple.Utils                     (defaultPackageDesc, die', notice, warn)
import System.IO                                     (hPutStr, stderr)

import qualified Data.ByteString  as BS
import qualified System.Directory as Dir

readGenericPackageDescriptionCheck :: Verbosity -> FilePath -> IO ([PWarning], GenericPackageDescription)
readGenericPackageDescriptionCheck verbosity fpath = do
    exists <- Dir.doesFileExist fpath
    unless exists $
      die' verbosity $
        "Error Parsing: file \"" ++ fpath ++ "\" doesn't exist. Cannot continue."
    bs <- BS.readFile fpath
    let (warnings, result) = runParseResult (parseGenericPackageDescription bs)
    case result of
        Left (_, errors) -> do
            traverse_ (warn verbosity . showPError fpath) errors
            hPutStr stderr $ renderParseError fpath bs errors warnings
            die' verbosity "parse error"
        Right x  -> return (warnings, x)

-- | Note: must be called with the CWD set to the directory containing
-- the '.cabal' file.
check :: Verbosity -> IO Bool
check verbosity = do
    pdfile <- defaultPackageDesc verbosity
    (ws, ppd) <- readGenericPackageDescriptionCheck verbosity pdfile
    -- convert parse warnings into PackageChecks
    let ws' = map (wrapParseWarning pdfile) ws
    -- flatten the generic package description into a regular package
    -- description
    -- TODO: this may give more warnings than it should give;
    --       consider two branches of a condition, one saying
    --          ghc-options: -Wall
    --       and the other
    --          ghc-options: -Werror
    --      joined into
    --          ghc-options: -Wall -Werror
    --      checkPackages will yield a warning on the last line, but it
    --      would not on each individual branch.
    --      However, this is the same way hackage does it, so we will yield
    --      the exact same errors as it will.
    let pkg_desc = flattenPackageDescription ppd
    ioChecks <- checkPackageFiles verbosity pkg_desc "."
    let packageChecks = ioChecks ++ checkPackage ppd (Just pkg_desc) ++ ws'
        buildImpossible = [ x | x@PackageBuildImpossible {} <- packageChecks ]
        buildWarning    = [ x | x@PackageBuildWarning {}    <- packageChecks ]
        distSuspicious  = [ x | x@PackageDistSuspicious {}  <- packageChecks ]
                          ++ [ x | x@PackageDistSuspiciousWarn {}  <- packageChecks ]
        distInexusable  = [ x | x@PackageDistInexcusable {} <- packageChecks ]

    unless (null buildImpossible) $ do
        warn verbosity "The package will not build sanely due to these errors:"
        printCheckMessages buildImpossible

    unless (null buildWarning) $ do
        warn verbosity "The following warnings are likely to affect your build negatively:"
        printCheckMessages buildWarning

    unless (null distSuspicious) $ do
        warn verbosity "These warnings may cause trouble when distributing the package:"
        printCheckMessages distSuspicious

    unless (null distInexusable) $ do
        warn verbosity "The following errors will cause portability problems on other environments:"
        printCheckMessages distInexusable

    let isDistError (PackageDistSuspicious     {}) = False
        isDistError (PackageDistSuspiciousWarn {}) = False
        isDistError _                              = True
        isCheckError (PackageDistSuspiciousWarn {}) = False
        isCheckError _                              = True
        errors = filter isDistError packageChecks

    unless (null errors) $
        warn verbosity "Hackage would reject this package."

    when (null packageChecks) $
        notice verbosity "No errors or warnings could be found in the package."

    return (not . any isCheckError $ packageChecks)

  where
    printCheckMessages :: [PackageCheck] -> IO ()
    printCheckMessages = traverse_ (warn verbosity) . map show
        -- xxx mapM_ o traverse?
