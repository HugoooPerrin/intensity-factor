


"""
Implementation of one-dimensional and multi-dimensional Kalman Filters

The Kalman Filter produces estimates of hidden variables when relying on inaccurate and uncertain measurements.
It belong to the α−β−γ filters family and can handle uncertainty in the dynamic model (unlike basic α−β−γ filter).

Its computations are based on five equations :
    * Two prediction equations:

      * State Extrapolation Equation - prediction or estimation of the future state, based on the known present estimation.
      * Covariance Extrapolation Equation - the measure of uncertainty in our prediction.

    * Two update equations:

      * State Update Equation - estimation of the current state, based on the known past estimation and present measurement.
      * Covariance Update Equation - the measure of uncertainty in our estimation.

    * Kalman Gain Equation – required for computation of the update equations. The Kalman Gain is actually a "weighting" parameter for the measurement and the past estimations. 
                            It defines the weight of the past estimation and the weight of the measurement in estimating the current state. 

Reference:
    * https://www.kalmanfilter.net/
"""


#--------------------------------------------- MODULES ---------------------------------------------


import pandas as pd
import numpy as np


#--------------------------------------------- 1D ---------------------------------------------


class KalmanFilter1D(object):

    def __init__(self, initial_estimate, initial_estimate_uncertainty, measurement_error, process_noise):

        self.process_noise = process_noise
        self.measurement_error = measurement_error

        self.current_estimate = initial_estimate
        self.measured_value = initial_estimate
        self.estimate_uncertainty = initial_estimate_uncertainty**2
        self.measurement_uncertainty = np.square(self.measurement_error)

        self._predict()

    def _measure(self, measured_value):
        self.measured_value = measured_value if not pd.isna(measured_value) else self.measured_value

    def _update(self):
        # Kalman gain equation
        self.kalman_gain = self.predicted_estimate_uncertainty / (self.predicted_estimate_uncertainty + self.measurement_uncertainty)
        # State update equation
        self.current_estimate = self.predicted_estimate + self.kalman_gain * (self.measured_value - self.predicted_estimate)
        # Covariance update equation
        self.estimate_uncertainty = (1 - self.kalman_gain) * self.estimate_uncertainty

    def _predict(self):
        # State extrapolation equation
        self.predicted_estimate = self.current_estimate
        # Covariance extrapolation equation
        self.predicted_estimate_uncertainty = self.estimate_uncertainty + self.process_noise

    def step(self, measured_value):
        self._measure(measured_value)
        self._update()
        self._predict()

    def get_current_estimate(self, measured_value):
        estimate = self.current_estimate
        self.step(measured_value)
        return estimate


#--------------------------------------------- MULTIDIMENSIONAL ---------------------------------------------


from numpy.linalg import inv


class KalmanFilter(object):
    """
    Kalman filter for constant ~~acceleration~~ velocity dynamic model
    """
    def __init__(self, initial_estimate, initial_estimate_uncertainty, measurement_error, process_noise):

        # CONSTANTS
        # Measurement error : scalar since only one measured value
        self.measurement_uncertainty = measurement_error**2

        # Measurement matrix
        self.H = np.array([1, 0])

        # Transition matrix describing chosen dynamic model
        self.F = np.array([[1, 1], [0, 1]])

        # Process noise matrix
        self.Q = process_noise**2 * np.array([[1/2, 1], [1, 1]])

        # INITIAL VALUES
        self.measured_value = np.array(initial_estimate)
        self.current_estimate = np.array(initial_estimate)
        self.estimate_uncertainty = initial_estimate_uncertainty * np.identity(2)

        # 1ST PREDICT
        self._state_extrapolation_equation()
        self._covariance_extrapolation_equation()

    # KALMAN EQUATIONS (5)
    def _state_update_equation(self):
        self.current_estimate = self.predicted_estimate + self.kalman_gain * (self.measured_value - self.predicted_estimate[0])

    def _covariance_update_equation(self):
        factor = np.identity(2) - np.outer(self.kalman_gain, self.H)
        self.estimate_uncertainty = (factor.dot(self.predicted_estimate_uncertainty).dot(factor.T)
                                     + self.measurement_uncertainty * np.outer(self.kalman_gain, self.kalman_gain))

    def _kalman_gain_equation(self):
        self.kalman_gain = self.predicted_estimate_uncertainty[:, 0] / (self.predicted_estimate_uncertainty[0, 0] + self.measurement_uncertainty)

    def _state_extrapolation_equation(self):
        self.predicted_estimate = self.F.dot(self.current_estimate)

    def _covariance_extrapolation_equation(self):
        self.predicted_estimate_uncertainty = self.F.dot(self.estimate_uncertainty).dot(self.F.T) + self.Q

    # ITERATIONS
    def step(self, measured_value):

        # Step 1 : measure
        self.measured_value = measured_value if not pd.isna(measured_value) else self.predicted_estimate[0]

        # Step 2 : update
        self._kalman_gain_equation()
        self._state_update_equation()
        self._covariance_update_equation()

        # Step 3 : predict
        self._state_extrapolation_equation()
        self._covariance_extrapolation_equation()

    # RENDER MAIN ESTIMATES
    def get_current_estimate(self, measured_value):
        estimate = self.current_estimate[0]
        self.step(measured_value)
        return estimate
