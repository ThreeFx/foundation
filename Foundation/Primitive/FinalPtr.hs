-- |
-- Module      : Foundation.Primitive.FinalPtr
-- License     : BSD-style
-- Maintainer  : Vincent Hanquez <vincent@snarc.org>
-- Stability   : experimental
-- Portability : portable
--
-- A smaller ForeignPtr reimplementation that work in any prim monad.
--
-- Here be dragon.
--
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}
{-# LANGUAGE CPP #-}
module Foundation.Primitive.FinalPtr
    ( FinalPtr(..)
    , finalPtrSameMemory
    , castFinalPtr
    , toFinalPtr
    , toFinalPtrForeign
    , withFinalPtr
    , withUnsafeFinalPtr
    , withFinalPtrNoTouch
    ) where

import GHC.Ptr
import GHC.ForeignPtr
import GHC.IO
import Foundation.Primitive.Monad
import Foundation.Internal.Primitive
import Foundation.Internal.Base

import Control.Monad.ST (runST)

-- | Create a pointer with an associated finalizer
data FinalPtr a = FinalPtr (Ptr a)
                | FinalForeign (ForeignPtr a)
instance Show (FinalPtr a) where
    show f = runST $ withFinalPtr f (return . show)
instance Eq (FinalPtr a) where
    (==) f1 f2 = runST (equal f1 f2)
instance Ord (FinalPtr a) where
    compare f1 f2 = runST (compare_ f1 f2)

-- | Check if 2 final ptr points on the same memory bits
--
-- it stand to reason that provided a final ptr that is still being referenced
-- and thus have the memory still valid, if 2 final ptrs have the
-- same address, they should be the same final ptr
finalPtrSameMemory :: FinalPtr a -> FinalPtr b -> Bool
finalPtrSameMemory (FinalPtr p1)     (FinalPtr p2)     = p1 == castPtr p2
finalPtrSameMemory (FinalForeign p1) (FinalForeign p2) = p1 == castForeignPtr p2
finalPtrSameMemory (FinalForeign _)  (FinalPtr _)      = False
finalPtrSameMemory (FinalPtr _)      (FinalForeign _)  = False

-- | create a new FinalPtr from a Pointer
toFinalPtr :: PrimMonad prim => Ptr a -> (Ptr a -> IO ()) -> prim (FinalPtr a)
toFinalPtr ptr finalizer = unsafePrimFromIO (primitive makeWithFinalizer)
  where
    makeWithFinalizer s =
        case compatMkWeak# ptr () (finalizer ptr) s of { (# s2, _ #) -> (# s2, FinalPtr ptr #) }

-- | Create a new FinalPtr from a ForeignPtr
toFinalPtrForeign :: ForeignPtr a -> FinalPtr a
toFinalPtrForeign fptr = FinalForeign fptr

-- | Cast a finalized pointer from type a to type b
castFinalPtr :: FinalPtr a -> FinalPtr b
castFinalPtr (FinalPtr a)     = FinalPtr (castPtr a)
castFinalPtr (FinalForeign a) = FinalForeign (castForeignPtr a)

withFinalPtrNoTouch :: FinalPtr p -> (Ptr p -> a) -> a
withFinalPtrNoTouch (FinalPtr ptr) f = f ptr
withFinalPtrNoTouch (FinalForeign fptr) f = f (unsafeForeignPtrToPtr fptr)
{-# INLINE withFinalPtrNoTouch #-}

-- | Looks at the raw pointer inside a FinalPtr, making sure the
-- data pointed by the pointer is not finalized during the call to 'f'
withFinalPtr :: PrimMonad prim => FinalPtr p -> (Ptr p -> prim a) -> prim a
withFinalPtr (FinalPtr ptr) f = do
    r <- f ptr
    primTouch ptr
    return r
withFinalPtr (FinalForeign fptr) f = do
    r <- f (unsafeForeignPtrToPtr fptr)
    unsafePrimFromIO (touchForeignPtr fptr)
    return r
{-# INLINE withFinalPtr #-}

-- | Unsafe version of 'withFinalPtr'
withUnsafeFinalPtr :: PrimMonad prim => FinalPtr p -> (Ptr p -> prim a) -> a
withUnsafeFinalPtr fptr f = unsafePerformIO (unsafePrimToIO (withFinalPtr fptr f))
{-# NOINLINE withUnsafeFinalPtr #-}

equal :: PrimMonad prim => FinalPtr a -> FinalPtr a -> prim Bool
equal f1 f2 =
    withFinalPtr f1 $ \ptr1 ->
    withFinalPtr f2 $ \ptr2 ->
        return $ ptr1 == ptr2
{-# INLINE equal #-}

compare_ :: PrimMonad prim => FinalPtr a -> FinalPtr a -> prim Ordering
compare_ f1 f2 =
    withFinalPtr f1 $ \ptr1 ->
    withFinalPtr f2 $ \ptr2 ->
        return $ ptr1 `compare` ptr2
{-# INLINE compare_ #-}
