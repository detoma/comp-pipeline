; docformat = 'rst'

;+
; Update comp_sci table with results of pipeline run for the given day.
;
; :Params:
;   date : in, required, type=string
;     date to process, in YYYYMMDD format
;   wave_type : in, required, type=string
;     wavelength range for the observations, '1074', '1079' or '1083'
;
; :Keywords:
;   database : in, required, type=MGdbMySQL object
;     database connection
;   obsday_index : in, required, type=integer
;     index into mlso_numfiles database table
;
; :Author:
;   MLSO Software Team
;-
pro comp_sci_insert, date, wave_type, database=db, obsday_index=obsday_index
  compile_opt strictarr

  mg_log, 'inserting rows into comp_sci table...', name='comp', /info

  ; find L1 files
  l1_files = comp_find_l1_files(date_dir, wave_type, /all, count=n_l1_files)
  
  ; angles for full circle in radians
  theta = findgen(360) * !dtor

  ; TODO: don't loop through all files
  ; loop through L1 files
  for f = 0L, n_l1_files - 1L do begin
    fits_open, l1_files[f], fcb
    fits_read, fcb, data, primary_header, exten_no=0, /no_abort, message=msg
    if (msg ne '') then message, msg
    date_obs = strin(sxpar(primary_header, 'DATE-OBS'), $
                     sxpar(primary_header, 'TIME-OBS'), $
                     format='(%"%sT%s")')

    ; TODO: calculate total{i,q,u}, intensity{,_stdev}, {q,u}{,_stddev},
    ; r{108,13}{i,l}, and r{108,13}radazi

    ; insert into comp_sci table
    fields = [{name: 'file_name', type: '''%s'''}, $
              {name: 'date_obs', type: '''%s'''}, $
              {name: 'obs_day', type: '%d'}, $
              {name: 'totali', type: '%f'}, $
              {name: 'totalq', type: '%f'}, $
              {name: 'totalu', type: '%f'}, $
              {name: 'intensity', type: '''%s'''}, $
              {name: 'intensity_stddev', type: '''%s'''}, $
              {name: 'q', type: '''%s'''}, $
              {name: 'q_stddev', type: '''%s'''}, $
              {name: 'u', type: '''%s'''}, $
              {name: 'u_stddev', type: '''%s'''}, $
              {name: 'r108i', type: '''%s'''}, $
              {name: 'r13i', type: '''%s'''}, $
              {name: 'r108l', type: '''%s'''}, $
              {name: 'r13l', type: '''%s'''}, $
              {name: 'r108radazi', type: '''%s'''}, $
              {name: 'r13radazi', type: '''%s'''}]
    sql_cmd = string(strjoin(fields.name, ', '), $
                     strjoin(fields.type, ', '), $
                     format='(%"INSERT INTO comp_sci (%s) VALUES (%s)")')
    db->execute, sql_cmd, $
                 file_basename(l1_files[f], '.gz'), $
                 date_obs, $
                 obsday_index, $
                 total_i, total_q, total_u, $
                 db->escape_string(intensity), $
                 db->escape_string(intensity_stdev), $
                 db->escape_string(q), $
                 db->escape_string(q_stddev), $
                 db->escape_string(u), $
                 db->escape_string(u_stddev), $
                 db->escape_string(r108i), $
                 db->escape_string(r13i), $
                 db->escape_string(r108l), $
                 db->escape_stringr(r13l), $
                 db->escape_string(r108radazi), $
                 db->escape_string(r13radazi), $
                 status=status, $
                 error_message=error_message, $
                 sql_statement=final_sql_cmd, $
                 n_warnings=n_warnings
    if (status ne 0L) then begin
      mg_log, 'error inserting into comp_sci table', name='comp', /error
      mg_log, 'status: %d, error message: %s', status, error_message, $
              name='comp', /error
      mg_log, 'SQL command: %s', final_sql_cmd, name='comp', /error
    endif

    if (n_warnings gt 0L) then comp_db_log_warnings, database=db

    fits_close, fcb
  endfor

  done:
  mg_log, 'done', name='comp', /info
end
