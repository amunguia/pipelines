module Pipeline (
      begin
    , end
    , input
    , output
    , waitOn
    , with
    , (&|)
    , (&/)
    ) where

import Control.Concurrent.Async (Async, async, link, link2, wait)
import Control.Concurrent.Chan

data JobResult a  = JobResult a | JobEnd 
data Runner  a b  = Runner {
                    job        :: a -> IO b
                  , inchan     :: Chan (JobResult a)
                  , outchan    :: Chan (JobResult b) 
                  } 
data Pipeline a b  = Pipeline {
                     startChan :: Chan (JobResult a) 
                   , endChan   :: Chan (JobResult b)
                   , startSync :: Async ()
                   , endSync   :: Async ()
                   }

exec :: Runner a b -> IO ()
exec runner = do
    a <- readChan $ inchan runner
    case a of 
        JobResult a' -> do
            b <- (job runner) a'
            writeChan (outchan runner) (JobResult b)
            exec runner 
        JobEnd -> do
            writeChan (inchan runner) JobEnd -- in case multiple readers
            writeChan (outchan runner) JobEnd
            return () 

toJobResultChan :: Chan a -> Chan (JobResult a) -> IO ()
toJobResultChan chan jobResultChan = do
    a <- readChan chan
    writeChan jobResultChan $ JobResult a
    toJobResultChan chan jobResultChan

makePipeline :: Chan (JobResult a) -> Chan (JobResult b) -> Async () -> Async () -> Pipeline  a b
makePipeline ichan ochan a1 a2 = Pipeline {startChan=ichan, endChan=ochan, startSync=a1, endSync=a2}

begin :: Chan a -> IO (Pipeline a a)
begin startChan = do
    chan <- newChan
    asyn <- async $ toJobResultChan startChan chan
    emp  <- async $ return ()
    return $ makePipeline chan chan asyn emp 

multiSync :: [Async ()] -> IO ()
multiSync syncs = do
    sequence_ $ fmap link syncs
    sequence_ $ fmap wait syncs
    return ()

(&|) :: IO (Pipeline c a) -> (a -> IO b) -> IO (Pipeline c b)
(&|) pipeline func = do 
    p          <- pipeline
    outChan    <- newChan
    let runner = Runner {job=func, inchan=(endChan p), outchan=outChan}
    asyn       <- async $ exec runner
    link2 asyn (startSync p)
    return $ makePipeline (startChan p) outChan (startSync p) asyn

(&/) :: IO (Pipeline c a) -> (a -> b) -> (IO (Pipeline c a), a -> b)
(&/) pipeline func = (pipeline, func)

with :: (IO (Pipeline c a), a -> IO b) ->  Int -> IO (Pipeline c b)
with (pipeline, func) num = do
    p          <- pipeline
    outChan    <- newChan
    let runner = Runner {job=func, inchan=(endChan p), outchan=outChan}
    asyns      <- sequence $ fmap (async . exec) $ replicate num runner
    asyn       <- async $ multiSync asyns
    link2 asyn (startSync p)
    return $ makePipeline (startChan p) outChan (startSync p) asyn

end :: Pipeline a b -> IO (Pipeline a b)
end pipeline = writeChan (startChan pipeline) JobEnd >> (return pipeline)

endAndWait :: Pipeline a b -> IO (Pipeline a b)
endAndWait pipeline = end pipeline >>= waitOn

input :: Pipeline a b -> a -> IO (Pipeline a b)
input pipeline a = writeChan (startChan pipeline) (JobResult a) >> (return pipeline)

output :: Pipeline a b -> IO (Maybe b)
output pipeline = do
    b <- readChan $ endChan pipeline
    case b of
        JobResult b -> return $ Just b
        JobEnd      -> return Nothing

waitOn :: Pipeline a b -> IO (Pipeline a b)
waitOn pipeline = wait (endSync pipeline) >> (return pipeline) 

