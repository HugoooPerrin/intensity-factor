import pandas as pd
import numpy as np

class Queue(object):

    def __init__(self, length):
        self.length = length
        self.queue = [pd.NA for _ in range(length)]

    def update(self, member):
        for i in range(self.length-1, 0, -1):
            self.queue[i] = self.queue[i-1]
        self.queue[0] = member

    def mean(self):
        return np.mean([e for e in self.queue if not pd.isna(e)])

    def current(self, n):
        return np.mean(self.queue[:n])

    def last(self, n):
        for i in range(self.length-1, n-2, -1):
            if not pd.isna(self.queue[i]):
                return np.mean(self.queue[i+1-n:i+1])
            else:
                continue
        return pd.NA

    def count_not_null(self):
        return len([e for e in self.queue if not pd.isna(e)])
