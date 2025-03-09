{-|
Copyright  :  (C) 2024-2025, Felix Klein
License    :  MIT (see the file LICENSE)
Maintainer :  Felix Klein <felix@qbaylogic.com>
-}

{-# LANGUAGE CPP #-}
{-# LANGUAGE NoStarIsType #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeOperators #-}

{-# OPTIONS_HADDOCK hide #-}

module Clash.Class.Finite.Internal.TH where

import Control.Monad (forM, replicateM)
#if !MIN_VERSION_base(4,20,0)
import Data.List (foldl')
#endif
import GHC.TypeNats (type (*))
import Language.Haskell.TH

#ifndef MAX_TUPLE_SIZE
#ifdef LARGE_TUPLES
#if MIN_VERSION_ghc(9,0,0)
import GHC.Settings.Constants (mAX_TUPLE_SIZE)
#else
import Constants (mAX_TUPLE_SIZE)
#endif
#define MAX_TUPLE_SIZE (fromIntegral mAX_TUPLE_SIZE)
#else
#define MAX_TUPLE_SIZE 12
#endif
#endif

maxTupleSize :: Num a => a
maxTupleSize = MAX_TUPLE_SIZE

-- | Contruct all the tuple instances (starting at size 3) for
-- 'Clash.Class.Finite.Internal.Finite'.
deriveFiniteTuples ::
  -- | Finite
  Name ->
  -- | ElementCount
  Name ->
  -- | elements
  Name ->
  -- | lowest
  Name ->
  -- | lowestMaybe
  Name ->
  -- | highest
  Name ->
  -- | highestMaybe
  Name ->
  -- | predMaybe
  Name ->
  -- | succMaybe
  Name ->
  -- | ith
  Name ->
  -- | index
  Name ->
  DecsQ
deriveFiniteTuples finiteName elementCountName elementsName lowestName
  lowestMaybeName highestName highestMaybeName predMaybeName succMaybeName
  ithName indexName
  = do
    let finite = ConT finiteName
        elementCount = ConT elementCountName
        times = ConT ''(*)

    allNames <- replicateM maxTupleSize $ newName "a"
    t2N <- newName "t2N"
    tN2 <- newName "tN2"
    x <- newName "x"

    forM [3..maxTupleSize] $ \tupleNum -> do
      let names = take tupleNum allNames
          (v,vs) = case map VarT names of
                      (z:zs) -> (z,zs)
                      _ -> error "maxTupleSize < 3"
          tuple xs = foldl' AppT (TupleT $ length xs) xs
          withConvContext b2N bN2 binds impl = return
            $ Clause binds (NormalB impl)
            $ ( if b2N then
                  (:) $ FunD t2N $ return
                    $ Clause
                        [ TupP [ p, TupP ps ]
                        | let (p,ps) = case map VarP names of
                                         (z:zs) -> (z,zs)
                                         _ -> error "maxTupleSize < 3"

                        ]
                        ( NormalB $ mkTupE $ map VarE names )
                        []
                else id
              )
            $ ( if bN2 then
                  (:) $ FunD tN2 $ return
                    $ Clause
                        [ TupP $ map VarP names ]
                        ( let (e,es) = case map VarE names of
                                         (z:zs) -> (z,zs)
                                         _ -> error "maxTupleSize < 3"
                          in NormalB (mkTupE [e,mkTupE es])
                        )
                        []
                else id
              )
              []

          -- Instance declaration
          context =
            [ finite `AppT` v
            , finite `AppT` tuple vs
            ]
          instTy = AppT finite $ tuple (v:vs)

          elementCountType =
            mkTySynInstD elementCountName [tuple (v:vs)]
              $ times `AppT` (elementCount `AppT` v) `AppT`
                (elementCount `AppT` foldl AppT (TupleT $ tupleNum - 1) vs)

          elements = FunD elementsName
            $ withConvContext True False []
            $ AppE (AppE (VarE '(<$>)) (VarE t2N))
            $ VarE elementsName

          lowest = FunD lowestName
            $ withConvContext True False []
            $ AppE (VarE t2N)
            $ VarE lowestName

          lowestMaybe = FunD lowestMaybeName
            $ withConvContext True False []
            $ AppE (AppE (VarE '(<$>)) (VarE t2N))
            $ VarE lowestMaybeName

          highest = FunD highestName
            $ withConvContext True False []
            $ AppE (VarE t2N)
            $ VarE highestName

          highestMaybe = FunD highestMaybeName
            $ withConvContext True False []
            $ AppE (AppE (VarE '(<$>)) (VarE t2N))
            $ VarE highestMaybeName

          predMaybe = FunD predMaybeName
            $ withConvContext True True [ VarP x ]
            $ AppE (AppE (VarE '(<$>)) (VarE t2N))
            $ AppE (VarE predMaybeName)
            $ AppE (VarE tN2)
            $ VarE x

          succMaybe = FunD succMaybeName
            $ withConvContext True True [ VarP x ]
            $ AppE (AppE (VarE '(<$>)) (VarE t2N))
            $ AppE (VarE succMaybeName)
            $ AppE (VarE tN2)
            $ VarE x

          ith = FunD ithName
            $ withConvContext True False [ VarP x ]
            $ AppE (VarE t2N)
            $ AppE (VarE ithName)
            $ VarE x

          index = FunD indexName
            $ withConvContext False True [ VarP x ]
            $ AppE (VarE indexName)
            $ AppE (VarE tN2)
            $ VarE x

      return $ InstanceD Nothing context instTy
        [ elementCountType
        , elements
        , lowest
        , lowestMaybe
        , highest
        , highestMaybe
        , predMaybe
        , succMaybe
        , ith
        , index
        ]
 where
  mkTupE = TupE
#if MIN_VERSION_template_haskell(2,16,0)
         . map Just
#endif


-- | Compatibility helper to create TySynInstD (stolen from Clash
-- Prelude, as it is not exported by the library)
mkTySynInstD :: Name -> [Type] -> Type -> Dec
mkTySynInstD tyConNm tyArgs rhs =
#if MIN_VERSION_template_haskell(2,15,0)
        TySynInstD (TySynEqn Nothing
                     (foldl AppT (ConT tyConNm) tyArgs)
                     rhs)
#else
        TySynInstD tyConNm
                   (TySynEqn tyArgs
                             rhs)
#endif
