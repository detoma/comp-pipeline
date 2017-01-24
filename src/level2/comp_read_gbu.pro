; docformat = 'rst'

;+
; Read a GBU log file.
;
; :Examples:
;   For example, call like::
;
;     cd, '/hao/kaula1/Data/CoMP/process/20120606'
;     gbu = comp_read_gbu('GBU.1079.log')
;
; :Uses:
;   merge_struct, str_sep, mg_log
;
; :Returns:
;   array of structures of the form::
;
;     { l1file:'', $
;       time_obs:'', $
;       quality:'', $
;       background:0., $
;       variance:0., $
;       wavelengths:0 }
;
; :Params:
;   gbu_file : in, required, type=string
;     GBU filename
;
; :Author:
;   Christian Bethge
;
; :History:
;   removed gzip    Oct 1 2014  GdT
;-
function comp_read_gbu, gbu_file, count=count
  compile_opt strictarr

  nlines = file_lines(gbu_file)
  count = nlines - 1
  sarr = strarr(nlines)
  openr, unit, gbu_file, /get_lun
  readf, unit, sarr
  free_lun, unit

  mg_log, 'GBU file %s has %d entries', file_basename(gbu_file), count, $
          name='comp', /debug

  if (count eq 0) then return, !null

  for ii = 1L, n_elements(sarr) - 1L do begin
    str = {l1file:'', $
           time_obs:'', $
           quality:'', $
           background:0., $
           variance:0., $
           wavelengths:0}
    x = str_sep(sarr[ii], ' ')
    best = where(x ne '', bc)
    x = x[best]
    str.l1file = x[0]

    file = x[0]
    ttt = str_sep(file, '.fts.gz')
    ttt = str_sep(ttt[0], '/')
    base = ttt[n_elements(ttt) - 1]

    ttt = str_sep(x[0], '.')
    time = strmid(ttt[0], 0, 4) $
             + '-' + strmid(ttt[0], 4, 2) $
             + '-' + strmid(ttt[0], 6, 2) $
             + ' ' + strmid(ttt[1], 0, 2) $
             + ':' + strmid(ttt[1], 2, 2) $
             + ':' + strmid(ttt[1], 4, 2)
    str.time_obs = time

    ; different generations of GBU file format
    if (n_elements(x) eq 4) then begin
      str.quality = x[1]
      str.background = 0.
      str.variance = float(x[2])
      str.wavelengths = fix(x[3])
    endif else begin
      str.quality = x[1]
      str.background = float(x[2])
      str.variance = float(x[3])
      str.wavelengths = fix(x[4])
    endelse

    ;   ofile = base+'.FitI.'+fns('#',str.wavelengths)+'.sav'
    ;   str.l2file = ofile

    if (ii eq 0) then gbu = str
    if (ii gt 0) then gbu = merge_struct(gbu, str)
  endfor

  mg_log, name='comp', logger=logger
  logger->getProperty, level=level
  if (level eq 5) then begin  ; 5 = debug
    good = where(gbu.quality eq 'Good', n_good)
    bad = where(gbu.quality eq 'Bad', n_bad)
    ugly = where(gbu.quality eq 'Ugly', n_ugly)

    mg_log, 'GBU file %s has %d good, %d bad, and %d ugly images', $
            file_basename(gbu_file), n_good, n_bad, n_ugly, $
            name='comp', /debug

    nfive = where(gbu.quality eq 'Good' and gbu.wavelengths eq 5, ng5)
    nthree = where(gbu.quality eq 'Good' and gbu.wavelengths eq 3, ng3)
    mg_log, '%d good 5pt files and %d good 3pt files', $
            ng5, ng3, name='comp', /debug
  endif

  return, gbu
end