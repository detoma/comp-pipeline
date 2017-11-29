; docformat = 'rst'

;+
; Sets up output filename for all the loggers defined in
; `comp_setup_loggers_loggers`.
;
; :Params:
;   date_dir : in, required, type=string
;     day of year to process, in YYYYMMDD format
;
; :Author:
;   MLSO Software Team
;-
pro comp_setup_loggers_date, date_dir
  compile_opt strictarr
  @comp_config_common

  if (~file_test(log_dir, /directory)) then file_mkdir, log_dir

  mg_log, name='comp', logger=logger
  logger->setProperty, filename=filepath(date_dir + '.log', root=log_dir)

  eng_dir = filepath('', subdir=comp_decompose_date(date_dir), root=engineering_dir)
  if (~file_test(eng_dir, /directory)) then file_mkdir, eng_dir

  for w = 0L, n_elements(process_wavelengths) - 1L do begin
    wl = process_wavelengths[w]
    mg_log, name='comp/crosstalk/' + wl, logger=logger
    basename = date_dir + '.comp.' + wl + '.crosstalk.txt'
    filename = filepath(basename, root=eng_dir)
    if (file_test(filename)) then file_delete, filename
    logger->setProperty, format='%(message)s', $
                         level=5, $
                         filename=filename
  endfor

  types = ['calc', 'flat']
  names = ['occ_ul', 'occ_lr', 'field_ul', 'field_lr']
  for t = 0L, n_elements(types) - 1L do begin
    for n = 0L, n_elements(names) - 1L do begin
      name = types[t] + '_' + names[n]
      filename = filepath(name + '.csv', root=eng_dir)
      if (file_test(filename)) then file_delete, filename
      mg_log, name=name, logger=logger
      logger->setProperty, format='%(message)s', $
                           level=5, $
                           filename=filename
    endfor
  endfor

  filename = filepath('occulter.csv', root=eng_dir)
  if (file_test(filename)) then file_delete, filename
  mg_log, name='occulter', logger=logger
  logger->setProperty, format='%(message)s', $
                       level=5, $
                       filename=filename
end


;+
; Sets up format and level for all the loggers defined in
; `comp_setup_loggers_loggers`.
;
; :Author:
;   MLSO Software Team
;-
pro comp_setup_loggers
  compile_opt strictarr
  @comp_config_common

  log_fmt = '%(time)s %(levelshortname)s: %(routine)s: %(message)s'
  log_time_fmt = '(C(CYI4, "-", CMOI2.2, "-", CDI2.2, " " CHI2.2, ":", CMI2.2, ":", CSI2.2))'
  mg_log, name='comp', logger=logger
  logger->setProperty, format=log_fmt, $
                       time_format=log_time_fmt, $
                       level=log_level
end
