from datetime import date, datetime
from dash import Dash, dcc, html, Input, Output
from flask import session
import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots
from firestore_query import get_data

METRICS = [('hrv', 'Heart rate variability', 'ms', '#2563eb'),
           ('bpm', 'Heart rate', 'bpm', '#b95f59'),
           ('steps', 'Steps', 'steps', '#688b56'),
           ('spo2', 'SpO₂', '%', '#647da8')]


def empty_chart(title, unit):
    fig = go.Figure()
    fig.update_layout(title=title, template='plotly_white', height=320,
                      margin=dict(l=55, r=25, t=55, b=40),
                      font=dict(family='system-ui', color='#172b4d'),
                      xaxis_title='Time', yaxis_title=unit)
    return fig


def add_dash(server):
    dash = Dash(__name__, server=server, routes_pathname_prefix='/dash/', title='Analytics')
    dash.layout = html.Div([
        dcc.Interval(id='auto-refresh', interval=60_000, n_intervals=0),
        html.Div([
            dcc.Dropdown(id='device-dropdown', options=[], placeholder='Select watch', style={'minWidth': '220px'}),
            dcc.DatePickerSingle(id='date-picker', date=date.today().isoformat(), display_format='MMM D, YYYY'),
            html.Button('Refresh', id='refresh', n_clicks=0, style={'padding': '10px 18px'})
        ], style={'display': 'flex', 'flexWrap': 'wrap', 'gap': '12px', 'padding': '16px'}),
        html.Div(id='query-status', role='status', style={'padding': '0 16px', 'color': '#63758f'}),
        html.Div(id='statistics-box', style={'display': 'flex', 'gap': '24px', 'flexWrap': 'wrap', 'padding': '20px'}),
        dcc.Graph(id='subplot-graph'),
        *[dcc.Graph(id=f'hourly-{key}-graph') for key, _, _, _ in METRICS],
    ], style={'fontFamily': 'system-ui', 'color': '#172b4d'})

    @dash.callback(Output('device-dropdown', 'options'), Input('refresh', 'n_clicks'))
    def watches(_):
        return [{'label': name, 'value': key} for key, name in session.get('device_ids', {}).items()]

    @dash.callback([Output('subplot-graph', 'figure'),
                    *[Output(f'hourly-{key}-graph', 'figure') for key, _, _, _ in METRICS],
                    Output('statistics-box', 'children'), Output('query-status', 'children')],
                   Input('device-dropdown', 'value'), Input('date-picker', 'date'), Input('refresh', 'n_clicks'), Input('auto-refresh', 'n_intervals'))
    def charts(watch, selected_date, _, tick=0):
        daily = make_subplots(rows=3, cols=1, shared_xaxes=True,
                              subplot_titles=['Heart rate variability', 'Heart rate', 'Steps'])
        daily.update_layout(template='plotly_white', height=650, showlegend=False,
                            margin=dict(l=60, r=25, t=55, b=40), font=dict(family='system-ui', color='#172b4d'))
        hourly = [empty_chart(title, unit) for _, title, unit, _ in METRICS]
        blank = [daily, *hourly, [], '']
        uid = session.get('user_id')
        if not uid or not watch or not selected_date:
            blank[-1] = 'Select a watch and date.'
            return blank
        if watch not in session.get('device_ids', {}):
            blank[-1] = 'Watch unavailable.'
            return blank
        try:
            day = datetime.strptime(selected_date[:10], '%Y-%m-%d').strftime('%m-%d-%Y')
            day_df, hour_df, _ = get_data(uid, watch, day)
        except Exception:
            server.logger.exception('Analytics query failed')
            blank[-1] = 'Could not load metrics. Try Refresh.'
            return blank
        stats = []
        any_values = False
        for index, (key, title, unit, color) in enumerate(METRICS):
            if index < 3:
                daily.update_yaxes(title_text=unit, row=index + 1, col=1)
            if index < 3 and key in day_df and 'Date' in day_df:
                values = pd.to_numeric(day_df[key], errors='coerce')
                dates = pd.to_datetime(day_df['Date'], format='%m-%d-%Y', errors='coerce')
                good = values.notna() & dates.notna()
                if good.any():
                    order = dates[good].sort_values().index
                    daily.add_trace(go.Scatter(x=dates.loc[order], y=values.loc[order], mode='lines+markers',
                                                line=dict(color=color), name=title), row=index+1, col=1)
                    value = values[good].sum() if key == 'steps' else values[good].mean()
                    label = 'Total steps' if key == 'steps' else title
                    stats.append(html.Div([html.Small(label), html.Div(f'{value:,.0f} {unit}' if key == 'steps'
                                                                                       else f'{value:,.1f} {unit}')]))
                    any_values = True
            if key in hour_df and 'Time' in hour_df:
                values = pd.to_numeric(hour_df[key], errors='coerce')
                times = pd.to_datetime(selected_date[:10] + ' ' + hour_df['Time'].astype(str), errors='coerce')
                good = values.notna() & times.notna()
                if good.any():
                    order = times[good].sort_values().index
                    hourly[index].add_trace(go.Scatter(x=times.loc[order], y=values.loc[order], mode='lines+markers',
                                                       line=dict(color=color), name=title))
                    any_values = True
        return [daily, *hourly, stats, '' if any_values else 'No processed metrics for this date.']
    return dash
