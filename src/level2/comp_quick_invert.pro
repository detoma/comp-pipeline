; docformat = 'rst'

;+
; Procedure to perform an approximate 'quick' inversion of some parameters from
; the comp averaged Level_2 data file. This routine reads the
; YYYYMMDD.comp.wwww.median.fts which was computed with `comp_average`, where
; "wwww" is the wave_type and "YYYYMMDD" is the date.
;
; The output is a FITS file written to the process directory named
; date_dir.comp.wwww.quick_invert.fts where "wwww" is the wave_type. The output
; FITS file contains extensions with the following images:
;
;   I - approximated by the Stokes I image nearest line center
;   Q - approximated by the Stokes Q image nearest line center
;   U - approximated by the Stokes U image nearest line center
;   Linear Polarization - computed as sqrt( Q^2 + U^2)
;   Azimuth - computed as 0.5 atan( U / Q)
;   Radial Azimuth
;   Doppler Velocity - computed from the analytic gaussian fit of the intensity
;                      of the three images nearest line center
;   Line Width - computed from the analytic gaussian fit of the intensity of
;                the three images nearest line center
;
; :Examples:
;   For example, call like::
;
;     comp_quick_invert, '20110504', '1074', /synthetic
;     comp_quick_invert, '20130915', '1074'
;
; :Uses:
;   comp_simulate_common, comp_constants_common, comp_config_common,
;   comp_azimuth, comp_analytic_gauss_fit2, fits_open, fits_read, fits_write,
;   fits_close, sxpar, sxaddpar, sxdelpar, mg_log
;
; :Params:
;   date_dir : in, required, type=string
;     date to process, in YYYYMMDD format
;   wave_type : in, required, type=string
;     wavelength range for the observations, '1074', '1079' or '1083'
;
; :Keywords:
;   synthetic : in, optional, type=boolean
;     process synthetic data set (not typically done)
;   error : out, optional, type=long
;     set to a named variable to return the error status of the routine, 0 for
;     success, anything else for failure
;   synoptic : in, optional, type=boolean
;     set to use synoptic file instead of waves file
;   method : in, optional, type=string, default='median'
;     set to 'mean' or 'median' to indicate the average files to use
;
; :Author:
;   MLSO Software Team
;
; :History:
;   removed gzip    Oct 1 2014  GdT
;   removed copy_file of intensity fits to archive_dir  Oct 1 2014  GdT
;   see git log for recent changes
;-
pro comp_quick_invert, date_dir, wave_type, $
                       synthetic=synthetic, error=error, synoptic=synoptic, $
                       method=method
  compile_opt idl2
  @comp_simulate_common
  @comp_constants_common
  @comp_config_common

  mg_log, 'quick invert %s (%s) [%s]', $
          wave_type, method, $
          keyword_set(synthetic) $
            ? 'synthetic' $
            : (keyword_set(synoptic) ? 'synoptic' : 'waves'), $
          name='comp', /info

  ; establish error handler for a crash in this routine
  catch, error
  if (error ne 0L) then begin
    catch, /cancel
    mg_log, /last_error, name='comp'
    return
  endif

  l2_process_dir = filepath('', subdir=[date_dir, 'level2'], root=process_basedir)
  cd, l2_process_dir

  _method = n_elements(method) eq 0L ? 'median' : method
  type = keyword_set(synoptic) ? 'synoptic' : 'waves'

  ; create filename and open input FITS file
  if (keyword_set(synthetic)) then begin
    file = string(date_dir, wave_type, format='(%"%s.comp.%s.synthetic.fts.gz")')
  endif else begin
    file = string(date_dir, wave_type, _method, type, format='(%"%s.comp.%s.%s.%s.fts.gz")')
  endelse

  if (~file_test(file) || file_test(file, /zero_length)) then begin
    mg_log, '%s not found', file, name='comp', /warn
    return
  endif

  fits_open, file, fcb
  n = fcb.nextend

  comp_inventory, fcb, beam, wavelengths, error=error
  if (error gt 0L) then begin
    mg_log, 'error reading %s', file, name='comp', /error
    goto, done
  endif

  ; copy the primary header from the median file to the output file
  fits_read, fcb, d, primary_header, /header_only, exten_no=0, $
             /no_abort, message=msg
  if (msg ne '') then begin
    fits_close, fcb
    mg_log, 'problem reading %s', file, name='comp', /error
    message, msg
  endif

  sxdelpar, primary_header, 'OBS_PLAN'
  sxdelpar, primary_header, 'OBS_ID'

  ntune = sxpar(primary_header, 'NTUNE', count=nrecords)
  if (nrecords eq 0L) then ntune = sxpar(primary_header, 'NTUNES')

  nstokes = n / ntune - 1L   ; don't count BKG

  if (nstokes lt 3L) then begin
    mg_log, 'only %d Stokes parameter%s in average file', $
            nstokes, nstokes ne 1 ? 's' : '', $
            name='comp', /warn
    mg_log, 'quitting', name='comp', /warn
    goto, done
  endif

  ; find standard 3 pt wavelength indices
  wave_indices = comp_3pt_indices(wave_type, wavelengths, error=error)
  if (error ne 0L) then begin
    mg_log, 'standard 3pt wavelengths not found in %s', $
            file_basename(file), name='comp', /error
  endif

  ; read data
  comp_obs = fltarr(nx, nx, nstokes, ntune)
  wave = fltarr(ntune)

  e = 1
  for is = 0L, nstokes - 1L do begin
    for iw = 0L, ntune - 1L do begin
      fits_read, fcb, dat, h, exten_no=e, /no_abort, message=msg
      if (msg ne '') then message, msg
      comp_obs[*, *, is, iw] = dat
      wave[iw] = sxpar(h, 'WAVELENG')
      ++e
    endfor
  endfor

  ; use header for center wavelength for I as template
  fits_read, fcb, dat, header, exten_no=ntune / 2, /no_abort, message=msg
  if (msg ne '') then message, msg

  fits_close, fcb

  sxaddpar, primary_header, 'N_EXT', 8, /savecomment

  case wave_type of
    '1074': begin
        rest = double(center1074)
        nominal = double(nominal_1074)
        int_min_thresh = int_min_1074_thresh
      end
    '1079': begin
        rest = double(center1079)
        nominal = double(nominal_1079)
        int_min_thresh = int_min_1079_thresh
      end
    '1083': begin
        rest = double(center1083)
        nominal = double(center1083)
        int_min_thresh = int_min_1079_thresh
      end
  endcase
  c = 299792.458D

  sxaddpar, primary_header, 'METHOD', _method, $
            ' Input file type used for quick invert'

  ; update version
  comp_l2_update_version, primary_header

  ; compute parameters
  i = comp_obs[*, *, 0, wave_indices[1]]
  q = comp_obs[*, *, 1, wave_indices[1]]
  u = comp_obs[*, *, 2, wave_indices[1]]

  zero = where(i le 0, count)
  if (count eq 0) then begin
    mg_log, 'no values less than 0 for %s nm intensity [%s] (%s)', $
            wave_type, _method, type, $
            name='comp', /warn
  endif

  ; compute azimuth and adjust for p-angle, correct azimuth for quadrants
  azimuth = comp_azimuth(u, q, radial_azimuth=radial_azimuth)

  i[zero] = 0.0
  azimuth[zero] = 0.0
  radial_azimuth[zero] = -999.0

  q[zero] = !values.f_nan
  u[zero] = !values.f_nan

  ; compute linear polarization
  l = sqrt(q^2 + u^2)

  ; compute doppler shift and linewidth from analytic gaussian fit
  i1 = comp_obs[*, *, 0L, wave_indices[0]]
  i2 = comp_obs[*, *, 0L, wave_indices[1]]
  i3 = comp_obs[*, *, 0L, wave_indices[2]]
  d_lambda = abs(wave[wave_indices[1]] - wave[wave_indices[0]])

  comp_analytic_gauss_fit2, i1, i2, i3, d_lambda, dop, width, peak_intensity
  dop += rest

  mask = comp_l2_mask(primary_header)
  no_post_mask = comp_l2_mask(primary_header, /no_post)

  good_pol_indices = where(mask gt 0 $
                             and i1 gt 0.05 $
                             and i2 gt 0.25 $
                             and i3 gt 0.05 $
                             and i1 lt 60.0 $
                             and i2 lt 60.0 $
                             and i3 lt 60.0, complement=bad_pol_indices, /null)

  q[bad_pol_indices]       = 0.0
  u[bad_pol_indices]       = 0.0
  l[bad_pol_indices]       = 0.0
  azimuth[bad_pol_indices] = 0.0

  ; TODO: should this be divided by sqrt(2.0) to give sigma?
  width *= c / wave[wave_indices[1]]

  pre_corr = dblarr(nx, ny, 2)
  pre_corr[*, *, 0] = peak_intensity
  pre_corr[*, *, 1] = dop

  comp_doppler_correction, pre_corr, post_corr, wave_type, ewtrend, temptrend, $
                           rest_wavelength=rest_wavelength
  if (abs(temptrend) gt 0.01) then begin
    mg_log, 'potential bad doppler correction: temptrend = %f', temptrend, $
            name='comp', /warn
  endif
  corrected_dop = reform(post_corr[*, *, 1])
  dop[zero] = !values.f_nan
  corrected_dop[zero] = !values.f_nan

  ; convert doppler from wavelength to velocity
  dop = (dop - rest) * c / nominal

  ; this is now the main rest wavelength calculation, we can remove all other
  ; calculations when we verify we like this one
  rest_wavelength = comp_compute_rest_wavelength(primary_header, $
                                                 dop, $
                                                 [[[i1]], [[i2]], [[i3]]], $
                                                 width, $
                                                 method='median')
  corrected_dop = dop - rest_wavelength

  good_vel_indices = where(mask gt 0 $
                             and dop ne 0 $
                             and abs(dop) lt 100 $
                             and i1 gt 0.1 $
                             and i2 gt int_min_thresh $
                             and i3 gt 0.1 $
                             and i1 lt 60.0 $
                             and i2 lt 60.0 $
                             and i3 lt 60.0 $
                             and width gt 22.0 $
                             and width lt 102.0, $
                           ngood, $
                           ncomplement=n_bad_vel_pixels, $
                           complement=bad_vel_indices, $
                           /null)
  if (n_bad_vel_pixels gt 0L) then begin
    dop[bad_vel_indices]           = !values.f_nan
    corrected_dop[bad_vel_indices] = !values.f_nan
    width[bad_vel_indices]         = !values.f_nan
  endif

  ; difference between calculated peak intensity and measured is not too great
  ind = where(abs(peak_intensity - i2) gt 1.5 * i2, count)
  if (count gt 0L) then begin
    dop[ind] = !values.f_nan
    corrected_dop[ind] = !values.f_nan
  endif

  ; apply geometric mask to all quantities in FITS file
  i[where(mask eq 0, /null)]              = !values.f_nan
  q[where(mask eq 0, /null)]              = !values.f_nan
  u[where(mask eq 0, /null)]              = !values.f_nan
  l[where(mask eq 0, /null)]              = !values.f_nan
  azimuth[where(mask eq 0, /null)]        = !values.f_nan
  corrected_dop[where(mask eq 0, /null)]  = !values.f_nan
  radial_azimuth[where(mask eq 0, /null)] = !values.f_nan
  dop[where(mask eq 0, /null)]            = !values.f_nan
  peak_intensity[where(mask eq 0, /null)] = !values.f_nan

  ; write fit parameters to output file

  quick_invert_filename = string(date_dir, wave_type, _method, type, $
                                 format='(%"%s.comp.%s.quick_invert.%s.%s.fts")')
  fits_open, quick_invert_filename, fcbout, /write

  ; copy the primary header from the median file to the output file
  fits_write, fcbout, 0, primary_header

  sxdelpar, header, 'POLSTATE'
  sxdelpar, header, 'WAVELENG'
  sxdelpar, header, 'DATATYPE'
  sxdelpar, header, 'FILTER'
  sxdelpar, header, 'COMMENT'

  sxaddpar, header, 'NTUNES', ntune
  sxaddpar, header, 'LEVEL   ', 'L2'

  sxaddpar, header, 'DATAMIN', min(i, /nan), ' minimum data value', format='(F0.3)'
  sxaddpar, header, 'DATAMAX', max(i, /nan), ' maximum data value', format='(F0.3)'
  fits_write, fcbout, i, header, extname='Center wavelength intensity'

  sxaddpar, header, 'DATAMIN', min(q, /nan), ' minimum data value', format='(F0.3)'
  sxaddpar, header, 'DATAMAX', max(q, /nan), ' maximum data value', format='(F0.3)'
  fits_write, fcbout, q, header, extname='Center wavelength Q'

  sxaddpar, header, 'DATAMIN', min(u, /nan), ' minimum data value', format='(F0.3)'
  sxaddpar, header, 'DATAMAX', max(u, /nan), ' maximum data value', format='(F0.3)'
  fits_write, fcbout, u, header, extname='Center wavelength U'

  sxdelpar, header, 'COMMENT'
  sxaddpar, header, 'DATAMIN', min(l, /nan), ' minimum data value', format='(F0.3)'
  sxaddpar, header, 'DATAMAX', max(l, /nan), ' maximum data value', format='(F0.3)'
  fits_write, fcbout, l, header, extname='Linear polarization'

  sxaddpar, header, 'COMMENT', $
            'Azimuth is measured positive counter-clockwise from the horizontal.'
  sxaddpar, header, 'DATAMIN', min(azimuth, /nan), ' minimum data value', format='(F0.3)'
  sxaddpar, header, 'DATAMAX', max(azimuth, /nan), ' maximum data value', format='(F0.3)'
  fits_write, fcbout, azimuth, header, extname='Azimuth'
  sxdelpar, header, 'COMMENT'

  sxaddpar, header, 'DATAMIN', min(corrected_dop, /nan), ' minimum data value', $
            format='(F0.3)'
  sxaddpar, header, 'DATAMAX', max(corrected_dop, /nan), ' maximum data value', $
            format='(F0.3)'

  fxaddpar, header, 'RSTWVL', rest_wavelength, $
            ' [km/s] rest wavelength', format='(F0.3)', /null

  fits_write, fcbout, corrected_dop, header, extname='Corrected LOS velocity'

  sxdelpar, header, 'RSTWVL'

  width_fwhm = width * fwhm_factor
  sxaddpar, header, 'DATAMIN', min(width_fwhm, /nan), ' minimum data value', format='(F0.3)'
  sxaddpar, header, 'DATAMAX', max(width_fwhm, /nan), ' maximum data value', format='(F0.3)'
  fits_write, fcbout, width_fwhm, header, extname='Line width (FWHM)'

  sxaddpar, header, 'DATAMIN', min(radial_azimuth, /nan), ' minimum data value', $
            format='(F0.3)'
  sxaddpar, header, 'DATAMAX', max(radial_azimuth, /nan), ' maximum data value', $
            format='(F0.3)'
  fits_write, fcbout, radial_azimuth, header, extname='Radial azimuth'

  if (add_uncorrected_velocity) then begin
    sxaddpar, header, 'DATAMIN', min(dop, /nan), ' minimum data value', $
              format='(F0.3)'
    sxaddpar, header, 'DATAMAX', max(dop, /nan), ' maximum data value', $
              format='(F0.3)'
    fxaddpar, header, 'RESTWVL', median_rest_wavelength, ' [km/s] rest wavelength', $
              format='(F0.3)', /null
    fxaddpar, header, 'ERESTWVL', east_median_rest_wavelength, $
              ' [km/s] east rest wavelength', format='(F0.3)', /null
    fxaddpar, header, 'WRESTWVL', west_median_rest_wavelength, $
              ' [km/s] west rest wavelength', format='(F0.3)', /null
    fits_write, fcbout, dop, header, extname='Uncorrected Doppler Velocity'
    sxdelpar, header, 'RESTWVL'
    sxdelpar, header, 'ERESTWVL'
    sxdelpar, header, 'WRESTWVL'
  endif

  sxaddpar, header, 'DATAMIN', min(peak_intensity, /nan), ' minimum data value', format='(F0.3)'
  sxaddpar, header, 'DATAMAX', max(peak_intensity, /nan), ' maximum data value', format='(F0.3)'
  fits_write, fcbout, peak_intensity, header, extname='Peak intensity'

  fits_close, fcbout

  zip_cmd = string(quick_invert_filename, format='(%"gzip -f %s")')
  spawn, zip_cmd, result, error_result, exit_status=status
  if (status ne 0L) then begin
    mg_log, 'problem zipping quick_invert file with command: %s', zip_cmd, $
            name='comp', /error
    mg_log, '%s', error_result, name='comp', /error
  endif

  done:
  fits_close, fcb

  mg_log, 'done', name='comp', /info
end
