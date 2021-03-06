{-# LANGUAGE FlexibleContexts, NoImplicitPrelude, RecordWildCards #-}

module Conflict
    ( Conflict(..), LineNo
    , prettyConflict, prettyConflictLines
    , parseConflicts
    , markerPrefix
    ) where

import           Control.Monad.State (MonadState, state, evalStateT)
import           Control.Monad.Writer (runWriter, tell)
import           Data.List (isPrefixOf)

import           Prelude.Compat

type LineNo = Int

data Conflict = Conflict
    { cMarkerA    :: (LineNo, String) -- <<<<<<<....
    , cMarkerBase :: (LineNo, String) -- |||||||....
    , cMarkerB    :: (LineNo, String) -- =======....
    , cMarkerEnd  :: (LineNo, String) -- >>>>>>>....
    , cLinesA     :: [String]
    , cLinesBase  :: [String]
    , cLinesB     :: [String]
    } deriving (Show)

prettyConflictLines :: Conflict -> [String]
prettyConflictLines Conflict {..} =
    concat
    [ snd cMarkerA    : cLinesA
    , snd cMarkerBase : cLinesBase
    , snd cMarkerB    : cLinesB
    , [snd cMarkerEnd]
    ]

prettyConflict :: Conflict -> String
prettyConflict = unlines . prettyConflictLines

-- '>' -> ">>>>>>>"
markerPrefix :: Char -> String
markerPrefix = replicate 7

breakUpToMarker :: MonadState [(LineNo, String)] m => Char -> m [(LineNo, String)]
breakUpToMarker c = state (break ((markerPrefix c `isPrefixOf`) . snd))

readHead :: MonadState [a] m => m (Maybe a)
readHead = state f
    where
        f [] = (Nothing, [])
        f (l:ls) = (Just l, ls)

tryReadUpToMarker :: MonadState [(LineNo, String)] m => Char -> m ([(LineNo, String)], Maybe (LineNo, String))
tryReadUpToMarker c =
    do
        ls <- breakUpToMarker c
        mHead <- readHead
        return (ls, mHead)

readUpToMarker :: MonadState [(LineNo, String)] m => Char -> m ([(LineNo, String)], (LineNo, String))
readUpToMarker c = do
    res <- tryReadUpToMarker c
    case res of
        (ls, Just h)  -> return (ls, h)
        (ls, Nothing) ->
            error $ concat
            [ "Parse error: failed reading up to marker: "
            , show c, ", got:"
            , concatMap (\(l,s) -> "\n" ++ show l ++ "\t" ++ s) $ take 5 ls
            ]

parseConflict :: MonadState [(LineNo, String)] m => (LineNo, String) -> m Conflict
parseConflict markerA =
    do  (linesA   , markerBase) <- readUpToMarker '|'
        (linesBase, markerB)    <- readUpToMarker '='
        (linesB   , markerEnd)  <- readUpToMarker '>'
        return Conflict
            { cMarkerA    = markerA
            , cMarkerBase = markerBase
            , cMarkerB    = markerB
            , cMarkerEnd  = markerEnd
            , cLinesA     = map snd linesA
            , cLinesB     = map snd linesB
            , cLinesBase  = map snd linesBase
            }

parseConflicts :: String -> [Either String Conflict]
parseConflicts input =
    snd $ runWriter $ evalStateT loop (zip [1..] (lines input))
    where
        loop =
            do  (ls, mMarkerA) <- tryReadUpToMarker '<'
                tell $ map (Left . snd) ls
                case mMarkerA of
                    Nothing -> return ()
                    Just markerA ->
                        do  tell . return . Right =<< parseConflict markerA
                            loop
