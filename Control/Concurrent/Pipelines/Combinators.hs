module Control.Concurrent.Pipelines.Combinators (
      (&|!)
    , (&|)
    , (&/!)
    , (&/)
    , (>=>)
    , (>=<)
    , with
    , withMonitor
    ) where

import Control.Concurrent.Async (async, link2, wait)
import Control.Concurrent.Chan
import Control.Exception (Exception, catch)

import Control.Concurrent.Pipelines.Internal

-- | Appends a new job to a pipeline.  Begins executing the new job
--   in a seperate thread.
(&|!) :: IO (Pipeline c a) -> (a -> IO b) -> IO (Pipeline c b)
(&|!) pipeline func = do 
    p        <- pipeline
    outChan  <- newChan
    let job  = Job {job=func, inchan=(endChan p), outchan=outChan}
    asyn     <- async $ exec job
    link2 asyn (startSync p)
    return $ makePipeline (startChan p) outChan (startSync p) asyn

-- | Like &|, except that the function being appended to a pipeline
--   does not run in IO.
(&|) :: IO (Pipeline c a) -> (a -> b) -> IO (Pipeline c b)
(&|) pipeline func = pipeline &|! (return . func)

-- | Intended to be followed by a call to with. Appends a new function
--   to a pipeline. However, this does not start a job. Following with 
--   a call to with starts the job running in the specified number of
--   threads.
--
--   Example usage:
--       pipeline :: IO (Pipeline c a)
--       f        :: a -> b
--       pipeline &/ f `with` 4  :: IO (Pipeline c b)
--
--   This will append f to the pipeline and it will execute in 4
--   threads.
(&/!) :: IO (Pipeline c a) -> (a -> IO b) -> (IO (Pipeline c a), a -> IO b)
(&/!) pipeline func = (pipeline, func)

-- | Like &/, except that the function being appended to a pipeline
--   does not run in IO.
(&/) :: IO (Pipeline c a) -> (a -> b) -> (IO (Pipeline c a), a -> IO b)
(&/) pipeline func = (pipeline, return . func)

-- | Specifies how many threads to execute the last job in pipeline.
with :: (IO (Pipeline c a), a -> IO b) ->  Int -> IO (Pipeline c b)
with (pipeline, func) num = do
    p       <- pipeline
    outChan <- newChan
    let job = Job {job=func, inchan=(endChan p), outchan=outChan}
    asyns   <- sequence $ fmap (async . exec) $ replicate num job
    asyn    <- async $ multiSync asyns
    link2 asyn (startSync p)
    return $ makePipeline (startChan p) outChan (startSync p) asyn
    
-- | Combines two pipelines into a larger pipeline.
(>=>) :: Pipeline a b -> Pipeline b c -> IO (Pipeline a c)
(>=>) pipeline1 pipeline2 = do 
    async $ shovel (endChan pipeline1) (startChan pipeline2) (startSync pipeline1)
    return $ makePipeline (startChan pipeline1) (endChan pipeline2) (startSync pipeline1) (endSync pipeline2)

-- | Branching operator. Ouput form the first pipeline is dupicated and sent through to
--   the other two pipelines.
(>=<) :: Pipeline a b -> Pipeline b c -> Pipeline b c -> IO ((Pipeline a c, Pipeline a c))
(>=<) startPipeline endPipeline1 endPipeline2 = do 
    dupedOut <- dupChan $ endChan startPipeline
    async $ shovel (endChan startPipeline) (startChan endPipeline1) (startSync startPipeline)
    async $ shovel dupedOut (startChan endPipeline2) (startSync startPipeline)
    let pipeline1 = makePipeline (startChan startPipeline) (endChan endPipeline1) (startSync startPipeline) (endSync endPipeline1)
    let pipeline2 = makePipeline (startChan startPipeline) (endChan endPipeline2) (startSync startPipeline) (endSync endPipeline2)
    return (pipeline1, pipeline2)

withMonitor :: Exception e => IO (Pipeline a b) -> (e -> IO ()) -> IO (Pipeline a b)
withMonitor pipeline monitor = do
    p   <- pipeline
    asyn <- async $ (wait (endSync p)) `catch` monitor
    return p