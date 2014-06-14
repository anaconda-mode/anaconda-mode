;;; anaconda-company.el --- Anaconda plugin for company-mode

;; Copyright (C) 2013, 2014 by Malyshev Artem

;; Authors: Malyshev Artem <proofit404@gmail.com>
;;          Fredrik Bergroth <fbergroth@gmail.com>
;; URL: https://github.com/proofit404/anaconda-mode
;; Version: 0.1.0

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;; Code:

(require 'company)
(require 'anaconda-mode)
(require 'anaconda-doc)
(require 'dash)
(require 'cl-lib)

(defvar company-anaconda-compact-annotation t
  "Show only the first character of type in annotations.")

(defun company-anaconda-prefix ()
  "Grab prefix at point.
Properly detect strings, comments and attribute access."
  (and (eq major-mode 'python-mode)
       (anaconda-mode-running-p)
       (not (company-in-string-or-comment))
       (or (company-grab-symbol-cons "\\." 1)
           'stop)))

(defun company-anaconda-candidates ()
  "Obtain candidates list from anaconda."
  (--map (propertize (plist-get it :name)
                     'item it)
         (anaconda-rpc-script "complete")))

(defun -get-prop (prop candidate)
  "Return the property PROP of completion candidate CANDIDATE."
  (let ((item (get-text-property 0 'item candidate)))
    (plist-get item prop)))

(defun company-anaconda-doc-buffer (candidate)
  "Return documentation buffer for chosen CANDIDATE."
  (let ((doc (-get-prop :doc candidate)))
    (and doc (anaconda-doc-buffer doc))))

(defun company-anaconda-meta (candidate)
  "Return short documentation string for chosen CANDIDATE."
  (-get-prop :short_doc candidate))

(defun company-anaconda-annotation (candidate)
  "Return annotation string for chosen CANDIDATE."
  (let ((annotation (-get-prop :annotation candidate)))
    (if company-anaconda-compact-annotation
        (substring annotation 0 1)
      annotation)))

(defun company-anaconda-location (candidate)
  "Return location (path . line) for chosen CANDIDATE."
  (-when-let* ((path (-get-prop :path candidate))
               (line (-get-prop :line candidate)))
    (cons path line)))

(defun company-anaconda (command &optional arg)
  "Jedi backend for company-mode.
See `company-backends' for more info about COMMAND and ARG."
  (interactive (list 'interactive))
  (cl-case command
    (interactive (company-begin-backend 'company-anaconda))
    (prefix (company-anaconda-prefix))
    (candidates (company-anaconda-candidates))
    (doc-buffer (company-anaconda-doc-buffer arg))
    (meta (company-anaconda-meta arg))
    (annotation (company-anaconda-annotation arg))
    (location (company-anaconda-location arg))
    (sorted t)))

(defun anaconda-company-handler (step)
  "Anaconda company plugin handler."
  (pcase step
    (`buffer-start
     (setq-local company-backends
                 (-difference (cons 'company-anaconda company-backends)
                              '(company-ropemacs)))
     (setq-local company-tooltip-align-annotations t)
     (company-mode 1))
    (`buffer-stop
     (kill-local-variable 'company-backends)
     (kill-local-variable 'company-tooltip-align-annotations)
     (company-mode -1))))

(provide 'anaconda-company)

;;; anaconda-company.el ends here
